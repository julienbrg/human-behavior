// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.29 <0.9.0;

import { IGroth16Verifier } from "../interfaces/IGroth16Verifier.sol";

/**
 * @title MockGroth16Verifier
 * @author W3HC
 * @notice Mock implementation of IGroth16Verifier for testing and development
 * @custom:security-contact julien@strat.cc
 * @dev This mock allows tests to control proof verification results without requiring actual zkSNARK verification.
 *      It provides two modes of operation:
 *      1. Default mode: All proofs return the same configured result (true or false)
 *      2. Explicit mode: Specific proof + publicInputs combinations can be marked as valid or invalid
 *
 *      This is useful for:
 *      - Testing HumanBehavior contract logic without zkSNARK infrastructure
 *      - Simulating both valid and invalid proof scenarios
 *      - Fast iteration during development
 *
 *      WARNING: This is a mock contract for testing only. Do NOT use in production.
 */
contract MockGroth16Verifier is IGroth16Verifier {
    // ============================================
    // State Variables
    // ============================================

    /// @notice Stores the validity status of explicitly configured proofs
    /// @dev Maps keccak256(abi.encode(proof, publicInputs)) to validity boolean
    mapping(bytes32 proofHash => bool isValid) public validProofs;

    /// @notice Tracks which proofs have been explicitly configured
    /// @dev Used to distinguish between explicitly set proofs and default behavior
    mapping(bytes32 proofHash => bool isConfigured) public isProofConfigured;

    /// @notice Default verification result for proofs not explicitly configured
    /// @dev If true, unconfigured proofs pass; if false, they fail
    bool public defaultResult;

    // ============================================
    // Configuration Functions
    // ============================================

    /**
     * @notice Sets the default verification result for all unconfigured proofs
     * @dev This allows tests to easily set up "accept all" or "reject all" scenarios
     *
     * @param _defaultResult True to accept all unconfigured proofs, false to reject them
     */
    function setDefaultResult(bool _defaultResult) external {
        defaultResult = _defaultResult;
    }

    /**
     * @notice Configures the verification result for a specific proof and public inputs combination
     * @dev This allows fine-grained control over which proofs should pass or fail in tests.
     *      Once set, this proof will return the configured result regardless of the defaultResult setting.
     *
     * @param proof The proof bytes to configure
     * @param publicInputs The public inputs associated with this proof
     * @param isValid Whether this specific proof should be considered valid
     */
    function setProofResult(bytes calldata proof, uint256[] calldata publicInputs, bool isValid) external {
        bytes32 proofHash = keccak256(abi.encode(proof, publicInputs));
        validProofs[proofHash] = isValid;
        isProofConfigured[proofHash] = true;
    }

    // ============================================
    // IGroth16Verifier Implementation
    // ============================================

    /**
     * @notice Verifies a Groth16 proof (mock implementation)
     * @dev Returns the configured result for this proof, or the default result if not configured.
     *      This does NOT perform actual cryptographic verification.
     *
     *      Lookup order:
     *      1. Check if this specific (proof, publicInputs) pair has been explicitly configured
     *      2. If yes, return the configured validity
     *      3. If no, return the default result
     *
     * @param proof The Groth16 proof bytes
     * @param publicInputs Array of public inputs to the circuit
     * @return True if the proof should be considered valid based on mock configuration, false otherwise
     */
    function verifyProof(
        bytes calldata proof,
        uint256[] calldata publicInputs
    )
        external
        view
        override
        returns (bool)
    {
        bytes32 proofHash = keccak256(abi.encode(proof, publicInputs));

        // If this specific proof has been explicitly configured, return the configured result
        if (isProofConfigured[proofHash]) {
            return validProofs[proofHash];
        }

        // Otherwise, return the default result
        return defaultResult;
    }
}
