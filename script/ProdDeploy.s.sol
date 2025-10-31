
// SPDX-License-Identifier: MIT
// Copyright (C) 2025 Soccerverse Ltd

pragma solidity ^0.8.19;

import "../src/ChiMigration.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Script } from "forge-std/Script.sol";

/* General data about the prod snapshot this represents:

Number of outputs: 601413
Total amount: 47457575.45408054 CHI
Merkle tree depth: 21 levels
Merkle root hash: 3bfb2a669620ad5624a706ffe95d9336614c67ce30111d8507e2f0dc3af9d213

*/

/**
 * @dev This script deploys the prod version of the snapshot
 * claiming contract.
 */
contract ProdDeployScript is Script
{

  IERC20 public constant WCHI
      = IERC20 (0x6DC02164d75651758aC74435806093E421b64605);
  bytes32 public constant ROOT_HASH
      = hex"3bfb2a669620ad5624a706ffe95d9336614c67ce30111d8507e2f0dc3af9d213";

  /**
   * The contract owner, which is able to handle claims of non-standard outputs
   * only, is set to the team multisig wallet.  This is the same wallet that
   * previously handled CHI/WCHI bridging manually.
   */
  address public constant OWNER = 0xb33B61AF1eA25b738Ef6677388fb75F436bC760f;

  function run () public
  {
    uint256 privkey = vm.envUint ("PRIVKEY");
    vm.startBroadcast (privkey);

    ChiMigration mig = new ChiMigration (WCHI, ROOT_HASH);
    mig.transferOwnership (OWNER);

    vm.stopBroadcast ();
  }

}
