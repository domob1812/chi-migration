
// SPDX-License-Identifier: MIT
// Copyright (C) 2024-2025 Soccerverse Ltd

pragma solidity ^0.8.19;

import "../src/ChiMigration.sol";
import "../test/TestToken.sol";

import { Script } from "forge-std/Script.sol";

/**
 * @dev This script deploys a dummy version of WCHI and the
 * migration contract with a random snapshot, so people can test
 * the migration in a real setting.
 */
contract TestDeployScript is Script
{

  function run () public
  {
    uint256 privkey = vm.envUint ("PRIVKEY");
    vm.startBroadcast (privkey);

    uint supply = 78e6 * 1e8;
    ERC20 token = new TestToken (supply);
    ChiMigration mig = new ChiMigration (
        token,
        hex"11bdff58145ec24b3f552bbb1b98b1cfa9d10f6e02b7b7d305db3355b6825f1f");
    require (token.transfer (address (mig), supply),
             "failed to send test tokens");

    vm.stopBroadcast ();
  }

}
