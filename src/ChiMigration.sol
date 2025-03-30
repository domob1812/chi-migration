// SPDX-License-Identifier: MIT
// Copyright (C) 2024-2025 The Xaya developers

pragma solidity ^0.8.13;

import "./MerkleClaim.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/**
 * @dev This is the main contract facilitating the claims process for
 * the CHI -> WCHI migration.  It is based on MerkleClaim and adds the
 * logic for authorising claims on top of it.
 *
 * This contract is owned.  The owners have the ability to authorise claims
 * for any of the "non-standard" outputs in the snapshot, i.e. outputs that
 * are not directly tied to a pubkeyhash on Xaya Core (such as P2SH or
 * any other scripts).  This allows those outputs to be still claimed, with
 * the original holders of those outputs proving ownership to the Xaya team.
 *
 * Apart from this special case, there is no other permission that the
 * contract owner (i.e. Xaya team) has.  It cannot upgrade the contract, nor
 * access any other funds (in particular not funds reserved for claims of
 * outputs that have a pubkeyhash associated).
 *
 * The claim via pubkeyhash works like this:  A special claim structure
 * is signed; this contains the output that is being claimed (txid and vout)
 * and the EVM address that the WCHI tokens should be sent to, and is
 * done via EIP712.  The signature is done by the same private key / public
 * key that owns/owned the CHI on Xaya.  To verify this, the signer passes
 * in their raw public key.  That then gets hashed with SHA-256/RIPEMD-160
 * and checked against the pubkeyhash from Xaya stored in the UTXO snapshot.
 * For this, both compressed and uncompressed format are tried.  Finally,
 * we also derive the associated EVM address (via Keccak / truncation)
 * from it, and verify that this address matches the EIP712 signature.
 *
 * Note that while the signature allows to recover the public key, this is
 * not exposed to Solidity (only the address of the recovered public key is).
 * For this reason, the claim needs to explicitly contain the public key, too.
 *
 * The EIP712 data hashed is this struct:
 *  struct PubKeyClaim
 *  {
 *    bytes32 txid;
 *    uint256 vout;
 *    address recipient;
 *  }
 */
contract ChiMigration is MerkleClaim, Ownable, EIP712
{

  string public constant EIP712_NAME = "ChiMigration";
  string public constant EIP712_VERSION = "1";

  /** @dev Error raised when the wrong claims process is used for a UTXO.  */
  error WrongClaimProcess (bytes32 txid, uint256 vout);

  /**
   * @dev Error raised when the pubkey claim proposes a pubkey that
   * does not match the UTXO's pubkeyhash.
   */
  error InvalidClaimPubKey (bytes32 txid, uint256 vout);

  /** @dev Error raised when the pubkey claim has an invalid signature.  */
  error InvalidClaimSignature (bytes32 txid, uint256 vout);

  constructor (IERC20 t, bytes32 r)
    MerkleClaim (t, r)
    Ownable (msg.sender)
    EIP712 (EIP712_NAME, EIP712_VERSION)
  {}

  /**
   * @dev Returns the EIP712 domain separator used for the data signed
   * by claimants with their Xaya pubkeys.
   */
  function domainSeparator ()
      public view returns (bytes32)
  {
    return _domainSeparatorV4 ();
  }

  /**
   * @dev Claims an output part of the snapshot that has no pubkeyhash
   * associated to it.  For this, the Xaya team performs an off-chain
   * check that the claimant has control over the output, and then can
   * execute this claim.
   */
  function claimNonStandard (UtxoData calldata utxo,
                             bytes32[] calldata merkleProof,
                             address recipient)
      public onlyOwner
  {
    if (uint160 (utxo.pubkeyhash) != 0)
      revert WrongClaimProcess (utxo.id.txid, utxo.id.vout);

    executeClaim (utxo, merkleProof, recipient);
  }

  /**
   * @dev Encodes a public key in either compressed or uncompressed format
   * and then computes the Xaya pubkeyhash from it.
   */
  function hashPubkey (uint256 pubkeyX, uint256 pubkeyY, bool compressed)
      private pure returns (bytes20)
  {
    bytes memory encoded;
    if (!compressed)
      encoded = abi.encodePacked (uint8 (0x04), pubkeyX, pubkeyY);
    else if (pubkeyY % 2 == 0)
      encoded = abi.encodePacked (uint8 (0x02), pubkeyX);
    else
      encoded = abi.encodePacked (uint8 (0x03), pubkeyX);

    return ripemd160 (abi.encodePacked (sha256 (encoded)));
  }

  /**
   * @dev Claims an output using a signature made by the private key
   * that corresponds to the pubkeyhash from the UTXO snapshot.
   */
  function claimWithPubKey (UtxoData calldata utxo,
                            bytes32[] calldata merkleProof,
                            address recipient,
                            uint256 pubkeyX, uint256 pubkeyY,
                            bytes calldata signature)
      public
  {
    if (uint160 (utxo.pubkeyhash) == 0)
      revert WrongClaimProcess (utxo.id.txid, utxo.id.vout);

    /* Check that the public key provided matches the Xaya pubkey hash.  We
       try both compressed and uncompressed format.  */
    if (hashPubkey (pubkeyX, pubkeyY, true) != utxo.pubkeyhash
          && hashPubkey (pubkeyX, pubkeyY, false) != utxo.pubkeyhash)
      revert InvalidClaimPubKey (utxo.id.txid, utxo.id.vout);

    /* Derive the EVM address corresponding to this same public key.  */
    bytes32 keccakHash = keccak256 (abi.encodePacked (pubkeyX, pubkeyY));
    address evmAddr = address (uint160 (uint256 (keccakHash)));

    /* Get EIP712 hash of the claim data.  */
    bytes memory body = abi.encode (
      keccak256 ("PubKeyClaim(bytes32 txid,uint256 vout,address recipient)"),
      utxo.id.txid,
      utxo.id.vout,
      recipient
    );
    bytes32 digest = _hashTypedDataV4 (keccak256 (body));

    /* Check signature against the expected pubkey EVM address.  */
    address signer = ECDSA.recover (digest, signature);
    if (signer != evmAddr)
      revert InvalidClaimSignature (utxo.id.txid, utxo.id.vout);

    executeClaim (utxo, merkleProof, recipient);
  }

}
