// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.29 <0.9.0;

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IGroth16Verifier } from "./interfaces/IGroth16Verifier.sol";

/**
 * @title HumanBehavior
 * @author W3HC
 * @notice Cross-chain permissionless registry for verifying human status using zkSNARK proofs
 * @custom:security-contact julien@strat.cc
 * @dev This contract is designed to be deployed at the same address across multiple chains using CREATE2.
 *
 *      Architecture:
 *      - HOME chain: Users holding a Human Passport SBT can link their stealth meta-address
 *      - FOREIGN chains: Anyone can prove ownership of a stealth address derived from a linked meta-address
 *
 *      Workflow:
 *      1. On HOME chain: SBT holder calls `link()` with their ERC-5564 stealth meta-address
 *      2. Off-chain: Relayers/indexers listen to `StealthMetaAddressLinked` events
 *      3. On ANY chain: User generates zkSNARK proof and calls `claim()` to verify a derived stealth address
 *
 *      The zkSNARK proof ensures privacy by proving correct ERC-5564 derivation without revealing:
 *      - The spending and viewing public keys
 *      - The ephemeral private key used for derivation
 */
contract HumanBehavior {
    // ============================================
    // State Variables
    // ============================================

    /// @notice Chain ID where human passport SBT verification occurs
    /// @dev This is the authoritative chain where `link()` can be called
    uint256 public immutable HOME;

    /// @notice Address of the Human Passport SBT contract on the home chain
    /// @dev Must implement IERC721 interface (e.g., Proof of Humanity, Worldcoin, etc.)
    address public immutable HUMAN_PASSPORT;

    /// @notice Groth16 verifier contract for validating ERC-5564 stealth address derivation proofs
    /// @dev Used to verify zkSNARK proofs in the `claim()` function
    IGroth16Verifier public immutable VERIFIER;

    /// @notice Tracks whether a stealth address has been verified as human on this chain
    /// @dev Set to true when `claim()` successfully verifies a zkSNARK proof
    mapping(address humanAddress => bool isHuman) public isHuman;

    /// @notice Tracks whether a stealth meta-address hash has been linked by a verified human
    /// @dev Uses hash instead of full 66-byte meta-address for gas efficiency
    ///      This mapping is populated on the HOME chain via `link()` and queried on all chains via `claim()`
    mapping(bytes32 metaAddressHash => bool isHumanMetaAddress) public isHumanMetaAddress;

    /// @notice Prevents a verified human from linking multiple meta-addresses on the HOME chain
    /// @dev Enforces one-to-one relationship between SBT holder and linked meta-address
    ///      Only checked on HOME chain in the `link()` function
    mapping(address humanAddress => bool hasLinked) public hasLinked;

    // ============================================
    // Events
    // ============================================

    /// @notice Emitted when a human successfully links their stealth meta-address on the HOME chain
    /// @dev Off-chain relayers should index this event to enable cross-chain verification
    /// @param metaAddressHash Keccak256 hash of the 66-byte ERC-5564 stealth meta-address
    /// @param humanAddress Address of the SBT holder who performed the linking
    event StealthMetaAddressLinked(bytes32 indexed metaAddressHash, address indexed humanAddress);

    /// @notice Emitted when a stealth address is successfully claimed as human on any chain
    /// @dev Indicates successful zkSNARK proof verification and human status assignment
    /// @param stealthAddress The derived stealth address now marked as human
    /// @param metaAddressHash The meta-address hash that was used to derive the stealth address
    event HumanStatusClaimed(address indexed stealthAddress, bytes32 indexed metaAddressHash);

    // ============================================
    // Errors
    // ============================================

    /// @notice Thrown when an invalid or zero address is provided for the Human Passport SBT
    error InvalidSBTAddress();

    /// @notice Thrown when a zero address is provided where a valid address is required
    error ZeroAddressNotAllowed();

    /// @notice Thrown when a user attempts to link a meta-address but has already linked one
    error AlreadyLinked();

    /// @notice Thrown when attempting to link without holding a Human Passport SBT on the HOME chain
    error NotVerifiedHumanOnHomeChain();

    /// @notice Thrown when the provided stealth meta-address is not exactly 66 bytes (ERC-5564 standard)
    error InvalidStealthMetaAddressLength();

    /// @notice Thrown when attempting to call a HOME chain only function on a different chain
    error ProofsOnlyOnHomeChain();

    /// @notice Thrown when zkSNARK proof verification fails or meta-address hash was never linked
    error InvalidHumanStatusProof();

    // ============================================
    // Modifiers
    // ============================================

    /// @notice Restricts function execution to the HOME chain only
    /// @dev Reverts with `ProofsOnlyOnHomeChain` if called on a different chain
    modifier onlyHomeChain() {
        if (block.chainid != HOME) revert ProofsOnlyOnHomeChain();
        _;
    }

    // ============================================
    // Constructor
    // ============================================

    /**
     * @notice Initializes the HumanBehavior registry with configuration for the home chain
     * @dev Should be deployed at the same address on all chains using CREATE2 for deterministic deployment
     * @param _home The chain ID where the Human Passport SBT contract is deployed and `link()` is callable
     * @param _humanPassport Address of the Human Passport SBT contract (must implement IERC721)
     * @param _verifier Address of the Groth16 verifier contract for zkSNARK proof verification
     * @custom:throws InvalidSBTAddress if _humanPassport is the zero address
     * @custom:throws ZeroAddressNotAllowed if _verifier is the zero address
     */
    constructor(uint256 _home, address _humanPassport, address _verifier) {
        if (_humanPassport == address(0)) {
            revert InvalidSBTAddress();
        }
        if (_verifier == address(0)) {
            revert ZeroAddressNotAllowed();
        }
        HOME = _home;
        HUMAN_PASSPORT = _humanPassport;
        VERIFIER = IGroth16Verifier(_verifier);
    }

    // ============================================
    // External Functions
    // ============================================

    /**
     * @notice Links an ERC-5564 stealth meta-address to the caller's verified human status
     * @dev This function can only be called on the HOME chain by addresses holding a Human Passport SBT.
     *      Once linked, the meta-address hash becomes globally verifiable across all chains via the `claim()` function.
     *
     *      Requirements:
     *      - Must be called on the HOME chain
     *      - Caller must own at least one Human Passport SBT token
     *      - Caller must not have previously linked a meta-address
     *      - Meta-address must be exactly 66 bytes (ERC-5564 standard)
     *
     *      State changes:
     *      - Sets `isHumanMetaAddress[keccak256(stealthMetaAddress)]` to true
     *      - Sets `hasLinked[msg.sender]` to true
     *
     * @param stealthMetaAddress The 66-byte ERC-5564 stealth meta-address to link (format: spending pubkey || viewing
     * pubkey)
     * @custom:throws InvalidStealthMetaAddressLength if stealthMetaAddress is not exactly 66 bytes
     * @custom:throws AlreadyLinked if caller has already linked a meta-address
     * @custom:throws NotVerifiedHumanOnHomeChain if caller does not own a Human Passport SBT
     * @custom:throws ProofsOnlyOnHomeChain if called on a chain other than HOME
     * @custom:emits StealthMetaAddressLinked
     */
    function link(bytes calldata stealthMetaAddress) external onlyHomeChain {
        if (stealthMetaAddress.length != 66) {
            revert InvalidStealthMetaAddressLength();
        }
        if (hasLinked[msg.sender]) {
            revert AlreadyLinked();
        }

        // Verify sender owns a Human Passport SBT on the HOME chain
        if (IERC721(HUMAN_PASSPORT).balanceOf(msg.sender) == 0) {
            revert NotVerifiedHumanOnHomeChain();
        }

        // Mark the hash of the stealth meta-address as human-verified
        bytes32 metaAddressHash = keccak256(stealthMetaAddress);
        isHumanMetaAddress[metaAddressHash] = true;
        hasLinked[msg.sender] = true;

        emit StealthMetaAddressLinked(metaAddressHash, msg.sender);
    }

    /**
     * @notice Claims human status for a stealth address by providing a zkSNARK proof of valid ERC-5564 derivation
     * @dev This function can be called on ANY chain (home or foreign) to verify a stealth address.
     *      The proof demonstrates that the stealth address was correctly derived from a linked meta-address
     *      without revealing the private keys or ephemeral secrets used in the derivation.
     *
     *      Requirements:
     *      - stealthAddress must not be the zero address
     *      - metaAddressHash must have been previously linked via `link()` on the HOME chain
     *      - zkProof must be a valid Groth16 proof demonstrating correct ERC-5564 derivation
     *
     *      The zkSNARK circuit verifies:
     *      1. Knowledge of the spending and viewing public keys that hash to metaAddressHash
     *      2. Knowledge of an ephemeral private key used in the derivation
     *      3. Correct ERC-5564 computation: stealthAddress = spendingPubKey + hash(sharedSecret) * G
     *
     *      State changes:
     *      - Sets `isHuman[stealthAddress]` to true
     *
     * @param stealthAddress The derived stealth address to verify and mark as human
     * @param metaAddressHash The keccak256 hash of the stealth meta-address used for derivation
     * @param zkProof The Groth16 zkSNARK proof in compressed format
     * @custom:throws ZeroAddressNotAllowed if stealthAddress is the zero address
     * @custom:throws InvalidHumanStatusProof if metaAddressHash was never linked or if zkProof verification fails
     * @custom:emits HumanStatusClaimed
     */
    function claim(address stealthAddress, bytes32 metaAddressHash, bytes calldata zkProof) external {
        if (stealthAddress == address(0)) {
            revert ZeroAddressNotAllowed();
        }

        // Verify that the meta address hash was linked by a verified human on the HOME chain
        if (!isHumanMetaAddress[metaAddressHash]) {
            revert InvalidHumanStatusProof();
        }

        // Prepare public inputs for the zkSNARK verifier
        uint256[] memory publicInputs = new uint256[](2);
        publicInputs[0] = uint256(uint160(stealthAddress));
        publicInputs[1] = uint256(metaAddressHash);

        // Verify the zkSNARK proof of correct ERC-5564 derivation
        bool proofValid = VERIFIER.verifyProof(zkProof, publicInputs);
        if (!proofValid) {
            revert InvalidHumanStatusProof();
        }

        // Mark the stealth address as human on this chain
        isHuman[stealthAddress] = true;

        emit HumanStatusClaimed(stealthAddress, metaAddressHash);
    }

    // ============================================
    // View Functions
    // ============================================

    /**
     * @notice Checks if a stealth meta-address has been linked as human on this chain
     * @dev Returns true if the meta-address hash exists in the `isHumanMetaAddress` mapping.
     *      This function is useful for verifying whether a meta-address was linked on the HOME chain
     *      and can be used to derive human-verified stealth addresses.
     *
     * @param metaAddress The 66-byte ERC-5564 stealth meta-address to check
     * @return True if the meta-address has been linked by a verified human, false otherwise
     */
    function isHumanMetaAddressOnChain(bytes calldata metaAddress) external view returns (bool) {
        if (metaAddress.length != 66) {
            return false;
        }
        return isHumanMetaAddress[keccak256(metaAddress)];
    }

    /**
     * @notice Checks if a standard address has been verified as human on this chain
     * @dev Returns true if the address was successfully claimed via the `claim()` function.
     *      This is the primary function for checking human status of regular addresses.
     *
     * @param addr The address to check for human verification status
     * @return True if the address has been verified as human, false otherwise
     */
    function isHumanOnChain(address addr) external view returns (bool) {
        return isHuman[addr];
    }
}
