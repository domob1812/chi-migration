#!/usr/bin/env python3

from flask import Flask, render_template, request, jsonify, session
import secrets
import argparse
import pickle
import sys
import json
import os
from web3 import Web3
from web3.middleware import ExtraDataToPOAMiddleware
from snapshot import UtxoSet

app = Flask(__name__)
app.secret_key = secrets.token_hex(16)  # Secure secret key for sessions

BATCH_SIZE = 500  # Maximum number of UTXOs to check in a single contract call
MAX_OUTPUTS = 2000  # Maximum number of outputs to process for an address

# Global variables
utxo_set = None
web3 = None
migration_contract = None

def load_utxo_data(filename):
    """Load the UTXO set from a pickle file."""
    try:
        with open(filename, 'rb') as f:
            return pickle.load(f)
    except Exception as e:
        print(f"Error loading UTXO data from {filename}: {e}", file=sys.stderr)
        sys.exit(1)

def load_contract_abi():
    """Load contract ABI from hardcoded JSON file path."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    abi_path = os.path.join(script_dir, 'abi/ChiMigration.json')
    
    try:
        with open(abi_path, 'r') as f:
            fulldata = json.load(f)
            return fulldata["abi"]
    except Exception as e:
        print(f"Error loading contract ABI from {abi_path}: {e}", file=sys.stderr)
        sys.exit(1)

def utxo_identifier(txid, vout):
    """
    Python implementation of the utxoIdentifier function from the smart contract.
    Returns the keccak256 hash of txid and vout packed together.
    """
    # Ensure txid is bytes
    if isinstance(txid, str):
        if txid.startswith('0x'):
            txid = bytes.fromhex(txid[2:])
        else:
            txid = bytes.fromhex(txid)
    
    # Pack txid and vout together
    packed = txid + vout.to_bytes(32, byteorder='big')
    
    # Return keccak256 hash
    return Web3.keccak(packed)

def batch_check_claimed(output_list):
    """
    Check which outputs have been claimed using the batchCheckClaimed method.
    
    Args:
        output_list: List of outputs to check, each with 'txid' and 'vout' keys
        
    Returns:
        Dictionary mapping (txid, vout) tuples to claimed status (True/False)
    """
    if migration_contract is None:
        raise RuntimeError("Migration contract not initialized")
    
    result = {}
    
    # Process in batches of BATCH_SIZE
    for i in range(0, len(output_list), BATCH_SIZE):
        batch = output_list[i:i + BATCH_SIZE]
        
        # Prepare the batch input for the contract call
        batch_identifiers = []
        for output in batch:
            batch_identifiers.append({
                'txid': output['txid'],
                'vout': output['vout']
            })
        
        # Make the contract call
        claimed_addresses = migration_contract.functions.batchCheckClaimed(batch_identifiers).call()
        
        # Process the results
        for j, output in enumerate(batch):
            claimed_address = claimed_addresses[j]
            is_claimed = claimed_address != '0x0000000000000000000000000000000000000000'
            result[(output['txid'], output['vout'])] = is_claimed
    
    return result

@app.route('/', methods=['GET', 'POST'])
def airdrop_claims():
    claims = []
    total_claimable = 0
    total_claimed = 0
    total_all = 0
    no_claims_found = False
    has_nonstandard = False
    address = ''
    too_many_outputs = False
    output_count = 0

    if request.method == 'POST':
        address = request.form.get('address', '')
        
        # Check claims availability using the UTXO set
        if utxo_set:
            # Get output indices for the address
            output_indices = utxo_set.lookupAddress(address)
            
            # Check if there are too many outputs
            if output_indices and len(output_indices) > MAX_OUTPUTS:
                too_many_outputs = True
                output_count = len(output_indices)
            else:
                # Determine if this address has nonstandard outputs
                if output_indices and utxo_set.outputs[output_indices[0]]['nonstandard']:
                    has_nonstandard = True
                
                # Prepare outputs for batch checking
                outputs_to_check = []
                for idx in output_indices:
                    outputs_to_check.append(utxo_set.outputs[idx])
                
                # Get claim status for all outputs in batches
                claim_status = {}
                if outputs_to_check:
                    claim_status = batch_check_claimed(outputs_to_check)
                
                # Process each output
                for idx in output_indices:
                    output = utxo_set.outputs[idx]
                    
                    # Get claimed status from our batch results
                    output_claimed = claim_status.get((output['txid'], output['vout']), False)
                    
                    # Format the claim data
                    claim = {
                        'txid': output['txid'],
                        'vout': output['vout'],
                        'amount': output['amount'],
                        'claimed': output_claimed,
                        'nonstandard': output['nonstandard']
                    }
                    claims.append(claim)
                
                # Calculate different totals
                total_claimable = sum(claim['amount'] for claim in claims 
                                if not claim.get('claimed', False))
                total_claimed = sum(claim['amount'] for claim in claims 
                                if claim.get('claimed', False))
                total_all = total_claimable + total_claimed
                
                no_claims_found = len(claims) == 0

                # Store data in session for use in claim modal
                session['claims'] = [
                    {
                        'txid': claim['txid'].hex(),
                        'vout': claim['vout'],
                        'amount': claim['amount'],
                        'claimed': claim.get('claimed', False),
                        'nonstandard': claim.get('nonstandard', False)
                    } 
                    for claim in claims
                ]
                session['total_claimable'] = total_claimable

    return render_template('index.html', 
                           claims=claims, 
                           total_claimable=total_claimable,
                           total_claimed=total_claimed,
                           total_all=total_all,
                           no_claims_found=no_claims_found,
                           has_nonstandard=has_nonstandard,
                           address=address,
                           too_many_outputs=too_many_outputs,
                           output_count=output_count)

@app.route('/execute-claim', methods=['POST'])
def execute_claim():
    """Execute a token claim using the provided private key and recipient address."""
    # Get form data
    private_key = request.form.get('private_key')
    claim_txid = request.form.get('claim_txid')
    claim_vout = request.form.get('claim_vout', type=int)
    wallet_address = request.form.get('wallet_address')
    
    # Validate inputs
    if not wallet_address:
        return jsonify({
            'success': False, 
            'error': 'Wallet not connected'
        }), 400
    
    if not private_key:
        return jsonify({
            'success': False, 
            'error': 'Private key is required'
        }), 400
    
    if not claim_txid:
        return jsonify({
            'success': False, 
            'error': 'Claim TXID is missing'
        }), 400
    
    if claim_vout is None:
        return jsonify({
            'success': False, 
            'error': 'Claim vout is missing'
        }), 400
    
    try:
        # Find the output index in the UTXO set
        txid_bytes = bytes.fromhex(claim_txid)
        output_index = utxo_set.lookupOutput(txid_bytes, claim_vout)
        
        if output_index is None:
            return jsonify({
                'success': False,
                'error': 'Output not found in UTXO set'
            }), 404
        
        # Check if the output is already claimed
        output = utxo_set.outputs[output_index]
        output_identifier = (output['txid'], output['vout'])
        is_claimed = batch_check_claimed([output])[output_identifier]
        
        if is_claimed:
            return jsonify({
                'success': False,
                'error': 'This output has already been claimed'
            }), 400
        
        # Get the Merkle proof for this output
        merkle_proof = utxo_set.getProof(output_index)
        
        # Sign the claim using the private key
        try:
            chain_id = web3.eth.chain_id
            contract_address = migration_contract.address
            
            x, y, signature = utxo_set.signClaim(
                output_index, 
                private_key, 
                wallet_address, 
                contract_address, 
                chain_id
            )
            
        except Exception as e:
            return jsonify({
                'success': False,
                'error': f'Failed to sign claim: {str(e)}'
            }), 400
        
        # Prepare the contract call
        try:
            # Structure the UTXO data as expected by the contract
            utxo_data = {
                'id': {
                  'txid': output['txid'],
                  'vout': output['vout'],
                },
                'amount': output['amount'],
                'pubkeyhash': output['pubkeyhash']
            }
            
            # Prepare transaction data for claimWithPubKey function
            tx = migration_contract.functions.claimWithPubKey(
                utxo_data,                 # UtxoData struct
                merkle_proof,              # Merkle proof
                wallet_address,            # recipient
                x,                         # pubkeyX
                y,                         # pubkeyY
                signature                  # signature as bytes
            ).build_transaction({
                'from': wallet_address,
                'gas': 200000,             # Gas limit
                'nonce': web3.eth.get_transaction_count(wallet_address),
            })
            
            # Return the transaction data to be signed by MetaMask in the frontend
            return jsonify({
                'success': True,
                'transaction': {
                    'to': tx['to'],
                    'from': tx['from'],
                    'data': tx['data'],
                    'gas': tx['gas'],
                    'amount': output['amount'] / 100000000,  # Convert to WCHI
                }
            })
            
        except Exception as e:
            return jsonify({
                'success': False,
                'error': f'Error preparing transaction: {str(e)}'
            }), 500
            
    except Exception as e:
        return jsonify({
            'success': False,
            'error': f'Unexpected error: {str(e)}'
        }), 500

if __name__ == '__main__':
    # Set up command line argument parsing
    parser = argparse.ArgumentParser(description='WCHI Token Airdrop Claims Application')
    parser.add_argument('--load', required=True, help='Path to the pickled UtxoSet file')
    parser.add_argument('--rpc-url', required=True, help='Ethereum RPC endpoint URL')
    parser.add_argument('--migration-contract', required=True, help='Migration contract address')
    
    # Parse arguments
    args = parser.parse_args()
    
    # Load UTXO data from pickle file
    utxo_set = load_utxo_data(args.load)
    
    # Connect to Ethereum and set up contract
    try:
        # Initialize Web3 connection
        web3 = Web3(Web3.HTTPProvider(args.rpc_url))
        web3.middleware_onion.inject(ExtraDataToPOAMiddleware, layer=0)
        if not web3.is_connected():
            print(f"Error: Could not connect to Ethereum node at {args.rpc_url}", file=sys.stderr)
            sys.exit(1)
        
        # Load contract ABI
        contract_abi = load_contract_abi()
        
        # Create contract instance
        migration_contract = web3.eth.contract(
            address=args.migration_contract,
            abi=contract_abi
        )
        
        print(f"Connected to Ethereum node, contract at {args.migration_contract}")
    except Exception as e:
        print(f"Error setting up Web3 or contract: {e}", file=sys.stderr)
        sys.exit(1)
    
    # Print stats about the loaded data
    print(f"Loaded UTXO set with {len(utxo_set.outputs)} outputs")
    print(f"Total claimable amount: {utxo_set.total}")
    
    app.run(debug=True)
