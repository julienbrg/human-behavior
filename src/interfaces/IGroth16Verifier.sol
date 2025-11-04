// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.29 <0.9.0;

/**
 * @title IGroth16Verifier
 * @author W3HC
 * @notice Interface for a Groth16 zkSNARK proof verifier contract
 * @custom:security-contact julien@strat.cc
 * @dev This interface defines the standard for verifying Groth16 zkSNARK proofs used in the HumanBehavior protocol.
 *      The verifier proves that a stealth address was correctly derived from a stealth meta-address
 *      following the ERC-5564 stealth address specification without revealing the private keys.
 *
 *      Expected circuit constraints:
 *      - Input 1: stealthAddress (the derived address to verify)
 *      - Input 2: metaAddressHash (keccak256 hash of the 66-byte stealth meta-address)
 *      - Private inputs: spending pubkey, viewing pubkey, ephemeral private key
 *      - Output: Boolean indicating valid ERC-5564 derivation
 */
interface IGroth16Verifier {
    /**
     * @notice Verifies a Groth16 zkSNARK proof with given public inputs
     * @dev The proof should be encoded in the standard compressed format used by most Groth16 implementations.
     *      This typically includes the three proof elements (A, B, C) from the pairing-based verification.
     *
     *      For the HumanBehavior protocol:
     *      - publicInputs[0]: The derived stealth address (as uint256)
     *      - publicInputs[1]: The keccak256 hash of the stealth meta-address (as uint256)
     *
     * @param proof The serialized Groth16 proof bytes
     * @param publicInputs Array of public inputs to the circuit
     * @return True if the proof is cryptographically valid and satisfies the circuit constraints, false otherwise
     */
    function verifyProof(bytes calldata proof, uint256[] calldata publicInputs) external view returns (bool);
}
