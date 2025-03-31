#!/usr/bin/env python3
# Copyright (C) 2025 The Xaya developers

"""
This script loads a UTXO snapshot and prints the addresses with the most
number of outputs in descending order.
"""

import argparse
import pickle


parser = argparse.ArgumentParser ()
parser.add_argument ("--load", required=True,
                     help="Load the UTXO Merkle tree from this file")
parser.add_argument ("--num", type=int, default=10,
                     help="Number of addresses to display")
args = parser.parse_args ()

with open (args.load, "rb") as f:
  utxos = pickle.load (f)

addressOutputCounts = [
  (address, len (outputs))
  for address, outputs in utxos.indexAddress.items ()
]

addressOutputCounts.sort (key=lambda x: x[1], reverse=True)

print (f"Top {args.num} addresses by output count:")
for i in range (min (args.num, len (addressOutputCounts))):
  address, count = addressOutputCounts[i]
  print (f"  #{i + 1} {address}: {count} outputs")
