#!/usr/bin/env python3
# Copyright (C) 2024 The Xaya developers

"""
This script looks up an address in the claim snapshot and prints
out all the outputs that are claimable (if any).
"""

import snapshot
import util

import argparse
import sys


parser = argparse.ArgumentParser ()
parser.add_argument ("--address", required=True,
                     help="Xaya address to look up")
args = parser.parse_args ()

utxos = snapshot.UtxoSet (sys.stdin)

ind = utxos.lookupAddress (args.address)

total = 0
print ("Outputs:")
for i in ind:
  o = utxos.outputs[i]
  total += o["amount"]
  print ("  %s:%d: %s CHI"
      % (o["txid"].hex (), o["vout"], util.formatChi (o["amount"])))

print ("\nTotal claimable: %s CHI" % util.formatChi (total))
