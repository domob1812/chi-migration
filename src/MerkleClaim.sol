// SPDX-License-Identifier: MIT
// Copyright (C) 2024-2025 The Xaya developers

pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @dev This is a base contract for claiming WCHI based on the Merkle snapshot
 * of the Xaya CHI UTXO snapshot.  It implements the Merkle logic handling UTXOs
 * but does not implement the mechanism to authorise a particular claim.
 */
contract MerkleClaim
{

  /**
   * @dev The "identifier" (txid and vout) for a particular UTXO.
   */
  struct UtxoIdentifier
  {

    /** @dev The txid on Xaya.  */
    bytes32 txid;

    /** @dev The vout value on Xaya.  */
    uint256 vout;

  }

  /**
   * @dev All data about a particular UTXO on the Xaya chain that is
   * part of the claim.  This is the leaf data inside the Merkle tree.
   */
  struct UtxoData
  {

    /** @dev The identifier of the UTXO.  */
    UtxoIdentifier id;

    /** @dev The value of the output in sats.  */
    uint256 amount;

    /**
     * @dev The pubkeyhash (RIPEMD-160) that is allowed to claim the output.
     * Set to zero for outputs that are non-standard (not associated to
     * a particular pubkey) and require manual claim.
     */
    bytes20 pubkeyhash;

  }

  /** @dev The token that is distributed by this contract (WCHI).  */
  IERC20 public immutable token;

  /** @dev The Merkle root hash.  */
  bytes32 public immutable rootHash;

  /**
   * @dev All outputs that have been claimed already.  The key into the
   * map is the keccak hash of (txid, vout).  The value is the EVM address
   * the token has been sent to.
   */
  mapping (bytes32 => address) public claimedOutputs;

  /** @dev Emitted when a claim is made successfully.  */
  event Claimed (bytes32 txid, uint vout, uint amount, address receiver);

  /**
   * @dev Error raised when a claim is attempted on an UTXO that has
   * already been claimed before.
   */
  error UtxoAlreadyClaimed (bytes32 txid, uint256 vout, address claimedBy);

  /**
   * @dev Error raised when a claim is invalid because the associated
   * Merkle proof does not work out.
   */
  error UtxoMerkleInvalid (bytes32 txid, uint256 vout);

  constructor (IERC20 t, bytes32 r)
  {
    token = t;
    rootHash = r;
  }

  /**
   * @dev Returns the "UTXO identifier hash" (txid and vout together)
   * that is the key into claimedOutputs for the given UTXO.
   */
  function utxoHash (UtxoIdentifier calldata id)
      public pure returns (bytes32)
  {
    return keccak256 (abi.encodePacked (id.txid, id.vout));
  }

  /**
   * @dev Checks a batch of UTXOs to see if they have been claimed already.
   */
  function batchCheckClaimed (UtxoIdentifier[] calldata ids)
      public view returns (address[] memory res)
  {
    res = new address[] (ids.length);
    for (uint i = 0; i < ids.length; ++i)
      res[i] = claimedOutputs[utxoHash (ids[i])];
  }

  /**
   * @dev Returns the leaf hash in our Merkle tree for the given UTXO.
   */
  function leafHash (UtxoData calldata utxo)
      public pure returns (bytes32)
  {
    return keccak256 (abi.encodePacked (
      utxo.id.txid,
      utxo.id.vout,
      utxo.amount,
      utxo.pubkeyhash
    ));
  }

  /**
   * @dev Checks if a given claim can be done, based on the Merkle proof
   * and that it is not yet claimed.  This does not check authorisation of
   * the caller to access the given output.
   *
   * Throws an appropriate error if the claim is not valid, otherwise
   * does nothing and succeeds.
   */
  function checkClaim (UtxoData calldata utxo, bytes32[] calldata merkleProof)
      public view
  {
    bytes32 id = utxoHash (utxo.id);
    address previousClaim = claimedOutputs[id];
    if (previousClaim != address (0))
      revert UtxoAlreadyClaimed (utxo.id.txid, utxo.id.vout, previousClaim);

    if (!MerkleProof.verifyCalldata (merkleProof, rootHash, leafHash (utxo)))
      revert UtxoMerkleInvalid (utxo.id.txid, utxo.id.vout);

    /* Otherwise the claim is fine from what we can tell.  */
  }

  /**
   * @dev Performs a claim with the given UTXO.  This assumes that the caller
   * has already verified that the recipient address is authorised to
   * receive the claim.
   */
  function executeClaim (UtxoData calldata utxo, bytes32[] calldata merkleProof,
                         address recipient)
      internal
  {
    require (recipient != address (0), "invalid recipient address");
    checkClaim (utxo, merkleProof);

    claimedOutputs[utxoHash (utxo.id)] = recipient;
    require (token.transfer (recipient, utxo.amount),
             "failed to transfer token for the claim");
    emit Claimed (utxo.id.txid, utxo.id.vout, utxo.amount, recipient);
  }

}
