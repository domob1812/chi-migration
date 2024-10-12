#!/usr/bin/env python3
# Copyright (C) 2024 The Xaya developers

"""
This script computes the Merkle root that is hardcoded in the claim
contract.  It is based on a CSV dump of the Xaya UTXO snapshot as
done by https://github.com/domob1812/bitcoin-utxo-dump (xaya branch).
"""

import snapshot
import util

import sys


utxos = snapshot.UtxoSet (sys.stdin)

print ("Number of outputs: %d" % len (utxos.outputs))
print ("Total amount: %s CHI" % util.formatChi (utxos.total))
print ("Merkle tree depth: %d levels" % len (utxos.levels))
print ("Merkle root hash: %s" % utxos.root.hex ())
