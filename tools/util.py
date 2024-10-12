#!/usr/bin/env python3
# Copyright (C) 2024 The Xaya developers

"""
Some utility methods for the scripts.
"""

from decimal import Decimal


def formatChi (val):
  """
  Formats a CHI value (in sats) as decimal string.
  """

  return str (Decimal ("0.00000001") * val)
