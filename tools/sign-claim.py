#!/usr/bin/env python3
# Copyright (C) 2024 The Xaya developers

"""
This script signs the claim for a particular pubkeyhash output in the snapshot.
"""

import snapshot

from web3 import Web3

import argparse
import sys


parser = argparse.ArgumentParser ()
parser.add_argument ("--txid", required=True,
                     help="TXID of the output to look up")
parser.add_argument ("--vout", type=int, required=True,
                     help="vout of the output to look up")
parser.add_argument ("--recipient", required=True,
                     help="Recipient address for the claimed tokens")
parser.add_argument ("--wif", required=True,
                     help="Xaya private key for the output in WIF")
parser.add_argument ("--contract", required=True,
                     help="Address of the ChiMigration contract")
parser.add_argument ("--chainid", type=int, required=True,
                     help="EVM chain ID for the EIP712 signature")
args = parser.parse_args ()

utxos = snapshot.UtxoSet (sys.stdin)

txid = Web3.to_bytes (hexstr=args.txid)
ind = utxos.lookupOutput (txid, args.vout)

if ind is None:
  sys.exit ("Unknown output")

x, y, sgn = utxos.signClaim (ind, args.wif, args.recipient,
                             args.contract, args.chainid)
print ("x = %064x" % x)
print ("y = %064x" % y)
print ("Signature: %s" % sgn.hex ())
