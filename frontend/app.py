#!/usr/bin/env python3

from flask import Flask, render_template, request, jsonify, session
import secrets

app = Flask(__name__)
app.secret_key = secrets.token_hex(16)  # Secure secret key for sessions

# Mock data with integers representing 10^-8 units of WCHI
MOCK_CLAIM_DATA = {
    'H83Xc9Qh5hNp1Tk7zVRSxjNLDRVFqrF3Ls': [
        {'txid': bytes.fromhex('1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'), 'vout': 0, 'amount': 12345678901},
        {'txid': bytes.fromhex('fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321'), 'vout': 1, 'amount': 6789012345},
        # New claims marked as already claimed
        {'txid': bytes.fromhex('abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890'), 'vout': 2, 'amount': 5000000000, 'claimed': True},
        {'txid': bytes.fromhex('9876543210fedcba9876543210fedcba9876543210fedcba9876543210fedcba'), 'vout': 3, 'amount': 2550000000, 'claimed': True}
    ]
}

@app.route('/', methods=['GET', 'POST'])
def airdrop_claims():
    claims = []
    total_claimable = 0
    total_claimed = 0
    total_all = 0
    no_claims_found = False
    address = ''

    if request.method == 'POST':
        address = request.form.get('address', '')
        
        # Check claims availability
        claims = MOCK_CLAIM_DATA.get(address, [])
        
        # Calculate different totals
        total_claimable = sum(claim['amount'] for claim in claims if not claim.get('claimed', False))
        total_claimed = sum(claim['amount'] for claim in claims if claim.get('claimed', False))
        total_all = total_claimable + total_claimed
        
        no_claims_found = len(claims) == 0

        # Store data in session for use in claim modal
        session['claims'] = claims
        session['total_claimable'] = total_claimable

    return render_template('index.html', 
                           claims=claims, 
                           total_claimable=total_claimable,
                           total_claimed=total_claimed,
                           total_all=total_all,
                           no_claims_found=no_claims_found,
                           address=address)

@app.route('/execute-claim', methods=['POST'])
def execute_claim():
    # Validate inputs
    private_key = request.form.get('private_key')
    claim_txid = request.form.get('claim_txid')
    wallet_address = request.form.get('wallet_address')
    
    # Check inputs
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
    
    # Mock claim execution verification
    # In a real application, you'd validate the private key and claim details
    return jsonify({
        'success': True, 
        'message': f'Claim for TXID {claim_txid} executed successfully to {wallet_address}!'
    })

if __name__ == '__main__':
    app.run(debug=True)
