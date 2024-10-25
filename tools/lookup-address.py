#!/usr/bin/env python3
# Copyright (C) 2024 The Xaya developers

"""
This script looks up an address in the claim snapshot and prints
out all the outputs that are claimable (if any).
"""

import util

import argparse
import pickle


parser = argparse.ArgumentParser ()
parser.add_argument ("--load", required=True,
                     help="Load the UTXO Merkle tree from this file")
parser.add_argument ("--address", required=True,
                     help="Xaya address to look up")
args = parser.parse_args ()

with open (args.load, "rb") as f:
  utxos = pickle.load (f)

ind = utxos.lookupAddress (args.address)

total = 0
print ("Outputs:")
for i in ind:
  o = utxos.outputs[i]
  total += o["amount"]
  print ("  %s:%d: %s CHI"
      % (o["txid"].hex (), o["vout"], util.formatChi (o["amount"])))

print ("\nTotal claimable: %s CHI" % util.formatChi (total))
