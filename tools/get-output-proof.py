#!/usr/bin/env python3
# Copyright (C) 2024 The Xaya developers

"""
This script takes a Merkle tree constructed from the UTXO dump CSV,
looks up a particular output, and returns the Merkle proof for it.
"""

import util

from web3 import Web3

import argparse
import pickle
import sys


parser = argparse.ArgumentParser ()
parser.add_argument ("--load", required=True,
                     help="Load the UTXO Merkle tree from this file")
parser.add_argument ("--txid", required=True,
                     help="TXID of the output to look up")
parser.add_argument ("--vout", type=int, required=True,
                     help="vout of the output to look up")
args = parser.parse_args ()

with open (args.load, "rb") as f:
  utxos = pickle.load (f)

txid = Web3.to_bytes (hexstr=args.txid)
ind = utxos.lookupOutput (txid, args.vout)

if ind is None:
  sys.exit ("Unknown output")

output = utxos.outputs[ind]
print ("Output data:")
print ("  amount: %s CHI" % util.formatChi (output["amount"]))
print ("  address: %s" % output["address"])
print ("  pubkeyhash: %s" % output["pubkeyhash"].hex ())

proof = utxos.getProof (ind)
print ("\nProof: [")
for p in proof:
  print ("  %s," % p.hex ())
print ("]")
