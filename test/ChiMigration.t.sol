// SPDX-License-Identifier: MIT
// Copyright (C) 2024 The Xaya developers

pragma solidity ^0.8.13;

import "./TestToken.sol";
import "../src/ChiMigration.sol";

import { Test } from "forge-std/Test.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

/*

For this test, we use a Merkle tree that contains outputs for all the
cases that are distinct:  Non-standard output (claimed by the contract owner),
as well as pubkeyhash outputs for compressed (even/odd) and uncompressed
public key.

We use these addresses for the pubkeyhash outputs:
  - CbyCzbUNDCqphFyCYodKE3byQaMtwSHVsD
    private key: LLMnfsCcMYReZHK9ZkTi4poovQHHKHErHvuTNv1PmkTAukPq2XiM
    pubkey compressed and even:
    02db4a4a1ceacab92d503c012500c61d0e5e9aecf48a886dedd882a45cb8a33eed
  - CcvVoEN3PBqg7H7ug6ECC9nyt7Df75RvFo
    private key: LLUphAnXc6LSHMwBNmbmJXEKtJj9j4gY4eL1JetakBZ2DJX3463d
    pubkey compressed and odd:
    032fa7dfca993d9629db6849ce65171e9174a4b9bb609d758080fc2bd1a7f7c26f
  - CX3MYs8tML2GtfshuWSah9N5dmmBiadAFx
    private key: 5PPsF3am9SvcSQdJRNDa8G5pdErsn5WCH6nPKufQdRSAK9FRSs6
    pubkey uncompressed:
    041505283de4a30c20a8b00a74be98297a5dc1056eb765f2da3e05ba444c47f8ff3e792742bf4fe71e63592b5838352aa0c3740809cef028d0a952210388144e54

txid,vout,amount,script,type,address
54cc0726bb4b9b6ea13f442011bc72c7b9cf5297c59ec24cb0421d3be0f5e701,1,1000,,p2sh,DLyZjsEXRFddHsmiW3jpngUGhnyGuApAy3
b9d964ea7b130ab3d691d99678da0cc8961ac5ca70e37e6fc6df4e9462360000,0,2000,,p2pk,CbyCzbUNDCqphFyCYodKE3byQaMtwSHVsD
b9d964ea7b130ab3d691d99678da0cc8961ac5ca70e37e6fc6df4e9462360000,1,3000,,p2pk,CcvVoEN3PBqg7H7ug6ECC9nyt7Df75RvFo
b9d964ea7b130ab3d691d99678da0cc8961ac5ca70e37e6fc6df4e9462360000,2,4000,,p2pk,CX3MYs8tML2GtfshuWSah9N5dmmBiadAFx

*/

/**
 * @dev A library with constants relating to the Merkle tree and UTXO snapshot
 * based on the test data from above.
 */
library TestData
{

  bytes32 internal constant rootHash
      = hex"7dc16cb53b6eb04f09625f64ed27af8c148ed044d576f077ebd4f36be9d72519";
  uint256 internal constant totalAmount = 10000;

  function getUtxo (uint ind)
      internal pure returns (MerkleClaim.UtxoData memory)
  {
    if (ind == 0)
      return MerkleClaim.UtxoData (
        hex"54cc0726bb4b9b6ea13f442011bc72c7b9cf5297c59ec24cb0421d3be0f5e701",
        1,
        1000,
        bytes20 (hex"0000000000000000000000000000000000000000")
      );
    if (ind == 1)
      return MerkleClaim.UtxoData (
        hex"b9d964ea7b130ab3d691d99678da0cc8961ac5ca70e37e6fc6df4e9462360000",
        0,
        2000,
        bytes20 (hex"d5f5d4f1e345e2751dd493c47cf8db64d1b7bf87")
      );
    if (ind == 2)
      return MerkleClaim.UtxoData (
        hex"b9d964ea7b130ab3d691d99678da0cc8961ac5ca70e37e6fc6df4e9462360000",
        1,
        3000,
        bytes20 (hex"e06abcaf02312af92516a11d2e131d3b6fa9fe68")
      );
    if (ind == 3)
      return MerkleClaim.UtxoData (
        hex"b9d964ea7b130ab3d691d99678da0cc8961ac5ca70e37e6fc6df4e9462360000",
        2,
        4000,
        bytes20 (hex"9fe6025e456877f43746f20d8707f1ab7d63e65c")
      );
    revert ("invalid index for test data");
  }

  function getProof (uint ind)
      internal pure returns (bytes32[] memory res)
  {
    res = new bytes32[] (2);

    if (ind == 0)
      {
        res[0] = hex"8c609d78d5a459d4725809c334690cb892e4b487361ed0f2181b7d0a3602dd49";
        res[1] = hex"07c7a2bf8565dd731ea214df8f9a69d941b7d29984c27fb687baf493aa0aed00";
      }
    else if (ind == 1)
      {
        res[0] = hex"243c2db6291ecc564891ae434d40234e2630c32bf47158177e265f969aeee0f3";
        res[1] = hex"07c7a2bf8565dd731ea214df8f9a69d941b7d29984c27fb687baf493aa0aed00";
      }
    else if (ind == 2)
      {
        res[0] = hex"1febfe3cec70f4fbe08fd8e90c9b9ec044285e6e03154d7bdc2d2eb256cb2c12";
        res[1] = hex"00d8af3a43c950e31413be1613f1e0f7490e6783c7b977d8c013f27bfdd65973";
      }
    else if (ind == 3)
      {
        res[0] = hex"be0bce74e401b47a9e9a6b200a78ee6c9737133728c7dfa4e4431ccc6cfcd657";
        res[1] = hex"00d8af3a43c950e31413be1613f1e0f7490e6783c7b977d8c013f27bfdd65973";
      }
    else
      revert ("invalid index for test data");
  }

  function getSignature (uint ind)
      internal pure returns (uint256 x, uint256 y, bytes memory sgn)
  {
    if (ind == 1)
      {
        x = 0xdb4a4a1ceacab92d503c012500c61d0e5e9aecf48a886dedd882a45cb8a33eed;
        y = 0x125ecde765875c12f44c647c46aae4ced8b16db37c6eaef830d8c9b0330b259e;
        sgn = hex"f3fb8f24bfde45715ab16bee5255d354320b20a3d70d40e96caeb22954708f901a87ea1a951e1b988bb41286b14f2f4f2cb45120ee92f39e478929e1699500061c";
      }
    else if (ind == 2)
      {
        x = 0x2fa7dfca993d9629db6849ce65171e9174a4b9bb609d758080fc2bd1a7f7c26f;
        y = 0x365b80173204a55f8ca604aab28698fbd25317d8d85910e62633d49153122801;
        sgn = hex"537aad26f950a89a3ac8f8065ef507b2bec64a98d1bc0fe28f6464e3175b65c201b71b5c30e6f41f2250a03e9baed0a8821ef7f5d90aa41287ae33096d4217b21b";
      }
    else if (ind == 3)
      {
        x = 0x1505283de4a30c20a8b00a74be98297a5dc1056eb765f2da3e05ba444c47f8ff;
        y = 0x3e792742bf4fe71e63592b5838352aa0c3740809cef028d0a952210388144e54;
        sgn = hex"0992ac17bd78a4d8ed59181368ca328d0ad51d2e9f63cbedb374f0e4db3401bb069d241064413a33674a298870abc806a5adafdf7519df59ec313f7ffcf124fa1b";
      }
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
    MerkleClaim.UtxoData memory utxo = TestData.getUtxo (0);
    bytes32[] memory proof = TestData.getProof (0);

    vm.expectPartialRevert (Ownable.OwnableUnauthorizedAccount.selector);
    vm.prank (alice);
    mig.claimNonStandard (utxo, proof, alice);

    vm.prank (owner);
    mig.claimNonStandard (utxo, proof, alice);
    assertEq (wchi.balanceOf (alice), utxo.amount);
  }

  function test_pubKeyClaim () public
  {
    vm.startPrank (alice);
    for (uint i = 1; i <= 3; ++i)
      {
        assertEq (wchi.balanceOf (alice), 0);
        MerkleClaim.UtxoData memory utxo = TestData.getUtxo (i);
        (uint256 x, uint256 y, bytes memory sgn) = TestData.getSignature (i);
        mig.claimWithPubKey (utxo, TestData.getProof (i), alice, x, y, sgn);
        assertEq (wchi.balanceOf (alice), utxo.amount);
        wchi.transfer (owner, utxo.amount);
      }
  }

  function test_pubKeyClaimInvalidPubKey () public
  {
    vm.expectPartialRevert (ChiMigration.InvalidClaimPubKey.selector);
    (uint256 x, uint256 y, bytes memory sgn) = TestData.getSignature (2);
    mig.claimWithPubKey (TestData.getUtxo (1), TestData.getProof (1), alice,
                         x, y, sgn);
  }

  function test_pubKeyClaimInvalidSignature () public
  {
    /* The EIP712 signature we use commits to the chain ID (among many
       other things).  So by mocking the chain ID, we make sure that the
       signature is invalid because it does not match the signed data anymore
       without invalidating anything else.  */
    vm.expectPartialRevert (ChiMigration.InvalidClaimSignature.selector);
    vm.chainId (123);
    (uint256 x, uint256 y, bytes memory sgn) = TestData.getSignature (1);
    mig.claimWithPubKey (TestData.getUtxo (1), TestData.getProof (1), alice,
                         x, y, sgn);
  }

  function test_wrongClaimProcess () public
  {
    vm.expectPartialRevert (ChiMigration.WrongClaimProcess.selector);
    vm.prank (owner);
    mig.claimNonStandard (TestData.getUtxo (1), TestData.getProof (1), alice);

    vm.expectPartialRevert (ChiMigration.WrongClaimProcess.selector);
    vm.prank (alice);
    (uint256 x, uint256 y, bytes memory sgn) = TestData.getSignature (1);
    mig.claimWithPubKey (TestData.getUtxo (0), TestData.getProof (0), alice,
                         x, y, sgn);
  }

}
