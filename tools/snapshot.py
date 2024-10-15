# Copyright (C) 2024 The Xaya developers

"""
This package contains the basic functionality to process the UTXO dump of
Xaya in CSV format (as created by https://github.com/domob1812/bitcoin-utxo-dump
on the "xaya" branch).  It can compute the claim Merkle tree from it,
and also provide information on additional addresses that they need to
claim their corresponding outputs.
"""

from eth_account import Account
from eth_account.messages import encode_structured_data
from web3 import Web3

from bip_utils import P2PKHAddrDecoder, P2WPKHAddrDecoder, WifDecoder
import coincurve

import csv
import hashlib
import multiprocessing


# Parameters for Xaya addresses.
ADDRVER = b"\x1c"
HRP = "chi"
WIFVER = b"\x82"

# Number of processes to use for building the UTXO set.  None means
# the number of processors in the system.
NUMPROC = None


def processRow (row):
  """
  Helper method that processes a row in the UTXO set dump.  It extracts
  the fields we want from it, converts from strings to more appropriate
  data types, and extracts the pubkeyhashes from the address (if any).
  """

  if row["type"] in ["p2pk", "p2pkh"]:
    pkh = P2PKHAddrDecoder.DecodeAddr (row["address"], net_ver=ADDRVER)
    addr = row["address"]
  elif row["type"] == "p2wpkh":
    pkh = P2WPKHAddrDecoder.DecodeAddr (row["address"], hrp=HRP)
    addr = row["address"]
  else:
    pkh = b"\0" * 20
    addr = None

  return {
    "txid": Web3.to_bytes (hexstr=row["txid"]),
    "vout": Web3.to_int (text=row["vout"]),
    "amount": Web3.to_int (text=row["amount"]),
    "pubkeyhash": pkh,
    "address": addr,
  }


def computeLeafHash (output):
  """
  Helper method to compute the Merkle leaf hash of an output.
  """

  return Web3.solidity_keccak (
      ["bytes32", "uint256", "uint256", "bytes20"],
      [output["txid"], output["vout"], output["amount"], output["pubkeyhash"]])


def hashPairs (pair):
  """
  Helper method to compute the hash of a pair of hashes, i.e. the parent
  node in the Merkle tree for two child nodes.  As per OpenZeppelin's
  MerkleProof contract, we hash the pair in sorted order.
  """

  (a, b) = pair

  if a < b:
    return Web3.keccak (a + b)

  return Web3.keccak (b + a)


class UtxoSet:
  """
  This class represents the "processed" UTXO set from the snapshot dump.

  During processing, we drop any name outputs, as they won't be part of the
  claim.  Outputs related to an address (p2pk, p2pkh, p2wpkh) will have
  their raw pubkeyhash computed, and any other outputs will be marked
  as non-standard (including p2sh and p2wsh).  Those can only be claimed
  by a manual check by the Xaya team.
  """

  def __init__ (self, inp):
    """
    Processes the CSV dump in the given input stream and builds up
    the processed data structure representing the UTXO set.
    """

    reader = csv.DictReader (inp)
    rows = [row for row in reader if row["type"] != "name"]

    with multiprocessing.Pool (NUMPROC) as p:
      outputs = p.map (processRow, rows)

    # Store the list of outputs as the initial main bit of data.
    self.outputs = outputs

    # Compute total balance.
    self.total = 0
    for o in self.outputs:
      self.total += o["amount"]

    # Build the Merkle tree.
    self.buildMerkle ()

    # Build the indices to look up outputs by txid or address.
    self.buildIndices ()

  def buildMerkle (self):
    """
    Builds (or rebuilds) the Merkle tree and root from the list of
    outputs in this instance.
    """

    # We store the hashes at each node in the Merkle tree.  This is done
    # row-by-row in an array of levels, where each level is the array
    # of corresponding node hashes.  The deepest level (with the hashes
    # of the leaves) is stored first.

    with multiprocessing.Pool (NUMPROC) as p:
      leafHashes = p.map (computeLeafHash, self.outputs)

      # Extend the size to a power of two.  We use all zeros as padding.
      nextPowerOfTwo = 1
      while nextPowerOfTwo < len (leafHashes):
        nextPowerOfTwo <<= 1
      leafHashes.extend ([b"\0" * 32] * (nextPowerOfTwo - len (leafHashes)))

      self.levels = [leafHashes]

      # Compute the next Merkle tree levels until we reach the root.
      while True:
        lastLevel = self.levels[-1]
        if len (lastLevel) == 1:
          break
        pairs = [
          (lastLevel[i], lastLevel[i + 1])
          for i in range (0, len (lastLevel), 2)
        ]
        nextLevel = p.map (hashPairs, pairs)
        self.levels.append (nextLevel)

    [self.root] = self.levels[-1]

  def buildIndices (self):
    """
    Builds (or rebuilds) indices to quickly look up outputs in self.outputs
    as required to find (and proof) claims for a specified UTXO or address.
    """

    # We build an index mapping txid to the (first) index for a UTXO with
    # this txid.  Search by vout can be done from there on linearly
    # (or could be a binary search but that is probably not necessary).
    #
    # In addition, we build an index mapping from addresses to a list of
    # indices of outputs that have the corresponding pubkeyhash.

    self.indexTxid = {}
    self.indexAddress = {}

    lastTxid = None
    for ind, o in enumerate (self.outputs):
      if o["txid"] != lastTxid:
        self.indexTxid[o["txid"]] = ind
        lastTxid = o["txid"]
      if o["address"] is not None:
        if o["address"] not in self.indexAddress:
          self.indexAddress[o["address"]] = []
        self.indexAddress[o["address"]].append (ind)

  def lookupOutput (self, txid, vout):
    """
    Returns the output index for the given txid:vout output.  Returns None
    if it is not part of the snapshot.
    """

    if txid not in self.indexTxid:
      return None

    ind = self.indexTxid[txid]
    while True:
      assert self.outputs[ind]["txid"] == txid
      if self.outputs[ind]["vout"] == vout:
        return ind
      ind += 1
      if ind >= len (self.outputs):
        return None
      if self.outputs[ind]["txid"] != txid:
        return None

  def lookupAddress (self, addr):
    """
    Returns a list of indices into the claim outputs that correspond
    to the given address.
    """

    if addr in self.indexAddress:
      return self.indexAddress[addr]

    return []

  def getProof (self, index):
    """
    Computes and returns the Merkle proof required for the output
    with the given index.  The proof is returned as array of bytes32
    hashes, as expected by the OpenZeppelin MerkleProof contract.
    """

    proof = []
    for lvl in self.levels[:-1]:
      if index % 2 == 0:
        proof.append (lvl[index + 1])
      else:
        proof.append (lvl[index - 1])
      index >>= 1

    return proof

  def signClaim (self, index, wif, recipient, verifyingContract, chainId):
    """
    Sign the claim message for the output at the given index with the
    private key passed in (as WIF) and for sending the claimed WCHI
    to the given recipient address.  For the EIP712 encoding, also the
    address of the claim contract and the chain ID are required.

    This method returns the pubkey point coordinates (x and y)
    and the signature bytes, as required to make the claim.
    """

    privKeyBytes, _ = WifDecoder.Decode (wif, net_ver=WIFVER)
    acc = Account.from_key (privKeyBytes)
    pubkey = coincurve.PublicKey.from_secret (privKeyBytes)

    o = self.outputs[index]

    # Check if the pubkey in either compressed or uncompressed form
    # yields the output's pubkeyhash.
    found = False
    for compressed in [True, False]:
      serialised = pubkey.format (compressed)
      pkhash = hashlib.sha256 (serialised).digest ()
      pkhash = hashlib.new ("ripemd160", pkhash).digest ()
      if pkhash == o["pubkeyhash"]:
        found = True
        break
    if not found:
      raise RuntimeError ("private key does not match output pubkeyhash")

    msg = {
      "domain": {
        "name": "ChiMigration",
        "version": "1",
        "chainId": chainId,
        "verifyingContract": verifyingContract,
      },
      "primaryType": "PubKeyClaim",
      "types": {
        "EIP712Domain": [
          {"name": "name", "type": "string"},
          {"name": "version", "type": "string"},
          {"name": "chainId", "type": "uint256"},
          {"name": "verifyingContract", "type": "address"},
        ],
        "PubKeyClaim": [
          {"name": "txid", "type": "bytes32"},
          {"name": "vout", "type": "uint256"},
          {"name": "recipient", "type": "address"},
        ],
      },
      "message": {
        "txid": o["txid"],
        "vout": o["vout"],
        "recipient": recipient,
      },
    }
    encoded = encode_structured_data (msg)
    signed = acc.sign_message (encoded)

    x, y = pubkey.point ()
    return x, y, signed.signature
