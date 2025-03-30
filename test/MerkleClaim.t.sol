// SPDX-License-Identifier: MIT
// Copyright (C) 2024-2025 The Xaya developers

pragma solidity ^0.8.13;

import "./TestToken.sol";
import "../src/MerkleClaim.sol";

import { Test } from "forge-std/Test.sol";

/*

For this test, we use a real Merkle tree and proofs constructed by
the tools scripts, based on a "minimal" but not trivial UTXO dump with
three outputs:

txid,vout,amount,script,type,address
098cc4e04ef868cfdbb5b07cedfcb17db12bb8b7d7742ee096c31682641f0000,0,4886594038,4f222fb1dea73baf3e664e087c017eacfbee5d07,p2pkh,CPgJuW5aWmr2yHMGsPs1u2WPbtDa9HzeQZ
b9d964ea7b130ab3d691d99678da0cc8961ac5ca70e37e6fc6df4e9462360000,0,382934346,03bdd752ec4d5a0556a5b1246517a2021673b00954c44931e584783dee2037c172,p2pk,CGdfj9xJ8CBdEPUJCkcrgZxDqA3snQTk4i
54cc0726bb4b9b6ea13f442011bc72c7b9cf5297c59ec24cb0421d3be0f5e701,1,7082837,adb48ef74c3fb9c80654a6cdba8269e28e615742,p2sh,DLyZjsEXRFddHsmiW3jpngUGhnyGuApAy3

*/

contract TestMerkleClaim is MerkleClaim
{

  constructor (IERC20 t, bytes32 r)
    MerkleClaim (t, r)
  {}

  function testExecuteClaim (UtxoData calldata utxo,
                             bytes32[] calldata merkleProof,
                             address recipient)
      public
  {
    executeClaim (utxo, merkleProof, recipient);
  }


}

/**
 * @dev A library with constants relating to the Merkle tree and UTXO snapshot
 * based on the test data from above.
 */
library TestData
{

  bytes32 internal constant rootHash
      = hex"782980bc9371e29b83614f4cc2490ead783c365434fb1aad216594b01481fd6e";
  uint256 internal constant totalAmount = 5276611221;

  function getUtxo (uint ind)
      internal pure returns (MerkleClaim.UtxoData memory)
  {
    if (ind == 0)
      return MerkleClaim.UtxoData (
        MerkleClaim.UtxoIdentifier (
          hex"098cc4e04ef868cfdbb5b07cedfcb17db12bb8b7d7742ee096c31682641f0000",
          0),
        4886594038,
        bytes20 (hex"4f222fb1dea73baf3e664e087c017eacfbee5d07")
      );
    if (ind == 1)
      return MerkleClaim.UtxoData (
        MerkleClaim.UtxoIdentifier (
          hex"b9d964ea7b130ab3d691d99678da0cc8961ac5ca70e37e6fc6df4e9462360000",
          0),
        382934346,
        bytes20 (hex"01d9705e11b738365b53ded2f79ed79bdf4a0bcf")
      );
    if (ind == 2)
      return MerkleClaim.UtxoData (
        MerkleClaim.UtxoIdentifier (
          hex"54cc0726bb4b9b6ea13f442011bc72c7b9cf5297c59ec24cb0421d3be0f5e701",
          1),
        7082837,
        bytes20 (hex"0000000000000000000000000000000000000000")
      );
    revert ("invalid index for test data");
  }

  function getProof (uint ind)
      internal pure returns (bytes32[] memory res)
  {
    res = new bytes32[] (2);

    if (ind == 0)
      {
        res[0] = hex"1cdf9c82c4e8d4210c8ef8677b9b2961e07d61f57aa1453d477af4a900da6481";
        res[1] = hex"e1a7317bfe43101af5813a0467825fd2731d935766a594e6715192d92934799f";
      }
    else if (ind == 1)
      {
        res[0] = hex"c683aa34cb0f084da49cf5d9c5307d6568f9dcf82f7cffe2ccabd1044536e6b3";
        res[1] = hex"e1a7317bfe43101af5813a0467825fd2731d935766a594e6715192d92934799f";
      }
    else if (ind == 2)
      {
        res[0] = hex"0000000000000000000000000000000000000000000000000000000000000000";
        res[1] = hex"2d2c7d5772b0b1d73f6af7e4b1f020611a6c376cd0cdc7d5b3fe7225b9078955";
      }
    else
      revert ("invalid index for test data");
  }

}

contract MerkleClaimTest is Test
{

  address public constant supply = address (1);
  address public constant alice = address (2);
  address public constant bob = address (3);

  TestToken public wchi;
  TestMerkleClaim public mc;

  constructor ()
  {
    vm.label (supply, "supply");
    vm.label (alice, "alice");
    vm.label (bob, "bob");
  }

  function setUp () public
  {
    vm.startPrank (supply);
    wchi = new TestToken (78e6 * 1e8);
    mc = new TestMerkleClaim (wchi, TestData.rootHash);
    wchi.transfer (address (mc), TestData.totalAmount);
    vm.stopPrank ();
  }

  function test_checkAllValidUtxos () public view
  {
    for (uint i = 0; i < 3; ++i)
      mc.checkClaim (TestData.getUtxo (i), TestData.getProof (i));
  }

  function test_invalidMerkleProof () public
  {
    MerkleClaim.UtxoData memory modified = TestData.getUtxo (0);
    modified.amount += 1;

    vm.expectPartialRevert (MerkleClaim.UtxoMerkleInvalid.selector);
    mc.checkClaim (modified, TestData.getProof (0));
  }

  function test_claimZeroAddress () public
  {
    vm.expectRevert ("invalid recipient address");
    mc.testExecuteClaim (TestData.getUtxo (0), TestData.getProof (0),
                         address (0));
  }

  function test_claimSuccess () public
  {
    MerkleClaim.UtxoData memory utxo0 = TestData.getUtxo (0);
    mc.testExecuteClaim (utxo0, TestData.getProof (0), alice);
    assertEq (wchi.balanceOf (alice), utxo0.amount);

    MerkleClaim.UtxoData memory utxo1 = TestData.getUtxo (1);
    mc.testExecuteClaim (utxo1, TestData.getProof (1), bob);
    assertEq (wchi.balanceOf (alice), utxo0.amount);
    assertEq (wchi.balanceOf (bob), utxo1.amount);

    mc.testExecuteClaim (TestData.getUtxo (2), TestData.getProof (2), alice);
    assertEq (wchi.balanceOf (alice), TestData.totalAmount - utxo1.amount);
    assertEq (wchi.balanceOf (bob), utxo1.amount);
    assertEq (wchi.balanceOf (address (mc)), 0);
  }

  function test_claimEvent () public
  {
    MerkleClaim.UtxoData memory utxo0 = TestData.getUtxo (0);

    vm.expectEmit (address (mc));
    emit MerkleClaim.Claimed (utxo0.id.txid, utxo0.id.vout,
                              utxo0.amount, alice);

    mc.testExecuteClaim (utxo0, TestData.getProof (0), alice);
  }

  function test_duplicateClaim () public
  {
    MerkleClaim.UtxoData memory utxo0 = TestData.getUtxo (0);
    mc.testExecuteClaim (utxo0, TestData.getProof (0), alice);
    assertEq (wchi.balanceOf (alice), utxo0.amount);

    vm.expectPartialRevert (MerkleClaim.UtxoAlreadyClaimed.selector);
    mc.testExecuteClaim (utxo0, TestData.getProof (0), alice);
  }

  function test_batchCheckClaimed () public
  {
    MerkleClaim.UtxoData memory utxo0 = TestData.getUtxo (0);
    MerkleClaim.UtxoData memory utxo1 = TestData.getUtxo (1);
    MerkleClaim.UtxoData memory utxo2 = TestData.getUtxo (2);

    mc.testExecuteClaim (utxo0, TestData.getProof (0), alice);
    mc.testExecuteClaim (utxo2, TestData.getProof (2), bob);

    MerkleClaim.UtxoIdentifier[] memory ids
        = new MerkleClaim.UtxoIdentifier[] (3);
    ids[0] = utxo0.id;
    ids[1] = utxo1.id;
    ids[2] = utxo2.id;

    address[] memory claimed = mc.batchCheckClaimed (ids);
    assertEq (claimed.length, 3);
    assertEq (claimed[0], alice);
    assertEq (claimed[1], address (0));
    assertEq (claimed[2], bob);
  }

}
