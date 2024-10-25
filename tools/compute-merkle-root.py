#!/usr/bin/env python3
# Copyright (C) 2024 The Xaya developers

"""
This script computes the Merkle root that is hardcoded in the claim
contract.  It is based on a CSV dump of the Xaya UTXO snapshot as
done by https://github.com/domob1812/bitcoin-utxo-dump (xaya branch).
"""

import snapshot
import util

import argparse
import pickle
import sys


parser = argparse.ArgumentParser ()
parser.add_argument ("--dump", default="",
                     help="Write the generated UTXO Merkle tree to this file")
args = parser.parse_args ()

utxos = snapshot.UtxoSet (sys.stdin)

if args.dump != "":
  with open (args.dump, "wb") as f:
    pickle.dump (utxos, f)

print ("Number of outputs: %d" % len (utxos.outputs))
print ("Total amount: %s CHI" % util.formatChi (utxos.total))
print ("Merkle tree depth: %d levels" % len (utxos.levels))
print ("Merkle root hash: %s" % utxos.root.hex ())
