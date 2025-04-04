// SPDX-License-Identifier: MIT
// Copyright (C) 2024-2025 The Xaya developers

pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @dev Minimal token that has its initial supply minted to
 * a given address on construction and can be used as token for testing.
 */
contract TestToken is ERC20
{

  constructor (uint supply)
    ERC20 ("Test Wrapped CHI", "TWCHI")
  {
    _mint (msg.sender, supply);
  }

  function decimals ()
      public pure override returns (uint8)
  {
    return 8;
  }

}
