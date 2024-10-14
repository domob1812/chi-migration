// SPDX-License-Identifier: MIT
// Copyright (C) 2024 The Xaya developers

pragma solidity ^0.8.13;

import "./TestToken.sol";
import "../src/ChiMigration.sol";

import { Test } from "forge-std/Test.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

/*

For this test, we use a Merkle tree that contains two outputs only,
one non-standard (that can be claimed by the contract owner) and one
with pubkeyhash that can be claimed by signature.  The private key
corresponding to the address CbyCzbUNDCqphFyCYodKE3byQaMtwSHVsD is
LLMnfsCcMYReZHK9ZkTi4poovQHHKHErHvuTNv1PmkTAukPq2XiM.

txid,vout,amount,script,type,address
b9d964ea7b130ab3d691d99678da0cc8961ac5ca70e37e6fc6df4e9462360000,0,1000,,p2pk,CbyCzbUNDCqphFyCYodKE3byQaMtwSHVsD
54cc0726bb4b9b6ea13f442011bc72c7b9cf5297c59ec24cb0421d3be0f5e701,1,7082837,adb48ef74c3fb9c80654a6cdba8269e28e615742,p2sh,DLyZjsEXRFddHsmiW3jpngUGhnyGuApAy3

*/

/**
 * @dev A library with constants relating to the Merkle tree and UTXO snapshot
 * based on the test data from above.
 */
library TestData
{

  bytes32 internal constant rootHash
      = hex"41dcd1878bdf4fa4df41e992ba9d91df960cbe1bc45f07d8353dd2ccbd0467dd";
  uint256 internal constant totalAmount = 7083837;

  function getUtxo (uint ind)
      internal pure returns (MerkleClaim.UtxoData memory)
  {
    if (ind == 0)
      return MerkleClaim.UtxoData (
        hex"b9d964ea7b130ab3d691d99678da0cc8961ac5ca70e37e6fc6df4e9462360000",
        0,
        1000,
        bytes20 (hex"d5f5d4f1e345e2751dd493c47cf8db64d1b7bf87")
      );
    if (ind == 1)
      return MerkleClaim.UtxoData (
        hex"54cc0726bb4b9b6ea13f442011bc72c7b9cf5297c59ec24cb0421d3be0f5e701",
        1,
        7082837,
        bytes20 (hex"0000000000000000000000000000000000000000")
      );
    revert ("invalid index for test data");
  }

  function getProof (uint ind)
      internal pure returns (bytes32[] memory res)
  {
    res = new bytes32[] (1);

    if (ind == 0)
      res[0] = hex"6952611c31fbf133b0c107762434975881d32e49c8688309172adef63ea466ee";
    else if (ind == 1)
      res[0] = hex"98aa417626ed37969be247c871b4aa5c9d2eb8a3614dcb5990a2e480823d0cc0";
    else
      revert ("invalid index for test data");
  }

}

contract ChiMigrationTest is Test
{

  address public constant owner = address (1);
  address public constant alice = address (2);

  TestToken public wchi;
  ChiMigration public mig;

  function setUp () public
  {
    vm.startPrank (owner);
    wchi = new TestToken (78e6 * 1e8);
    mig = new ChiMigration (wchi, TestData.rootHash);
    wchi.transfer (address (mig), TestData.totalAmount);
    vm.stopPrank ();
  }

  function test_nonStandardClaim () public
  {
    MerkleClaim.UtxoData memory utxo = TestData.getUtxo (1);
    bytes32[] memory proof = TestData.getProof (1);

    vm.expectPartialRevert (Ownable.OwnableUnauthorizedAccount.selector);
    vm.prank (alice);
    mig.claimNonStandard (utxo, proof, alice);

    vm.prank (owner);
    mig.claimNonStandard (utxo, proof, alice);
    assertEq (wchi.balanceOf (alice), utxo.amount);
  }

  function test_wrongClaimProcess () public
  {
    vm.expectPartialRevert (ChiMigration.WrongClaimProcess.selector);
    vm.prank (owner);
    mig.claimNonStandard (TestData.getUtxo (0), TestData.getProof (0), alice);
  }

}
