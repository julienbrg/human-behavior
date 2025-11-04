// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.29 <0.9.0;

import { Script } from "forge-std/src/Script.sol";

/**
 * @title BaseScript
 * @author W3HC
 * @notice Base contract for Foundry deployment and interaction scripts
 * @custom:security-contact julien@strat.cc
 * @dev Provides common functionality for all deployment scripts including:
 *      - Flexible broadcaster configuration via environment variables
 *      - Support for both direct address specification and mnemonic derivation
 *      - Broadcast modifier for transaction execution
 *      - Constants for deterministic deployments
 *
 *      Usage:
 *      1. Inherit from this contract in your deployment scripts
 *      2. Use the `broadcast` modifier on functions that execute transactions
 *      3. Set either $ETH_FROM or $MNEMONIC environment variable
 */
abstract contract BaseScript is Script {
    // ============================================
    // Constants
    // ============================================

    /// @notice Default mnemonic used when no environment variable is set
    /// @dev This is the standard test mnemonic from Foundry, allowing scripts to run without configuration
    string internal constant TEST_MNEMONIC = "test test test test test test test test test test test junk";

    /// @notice Salt value for CREATE2 deterministic deployments
    /// @dev Using zero salt for simplicity; can be overridden in child contracts if needed
    bytes32 internal constant ZERO_SALT = bytes32(0);

    // ============================================
    // State Variables
    // ============================================

    /// @notice The address that will broadcast transactions
    /// @dev Set during constructor based on environment variables
    address internal broadcaster;

    /// @notice The mnemonic phrase used to derive the broadcaster address
    /// @dev Only used when $ETH_FROM is not set
    string internal mnemonic;

    // ============================================
    // Constructor
    // ============================================

    /**
     * @notice Initializes the broadcaster address from environment variables
     * @dev Initialization priority:
     *      1. If $ETH_FROM is set, use that address directly
     *      2. Otherwise, derive from $MNEMONIC (or TEST_MNEMONIC if not set) at index 0
     *
     *      Environment Variables:
     *      - ETH_FROM: Directly specifies the broadcaster address (useful with hardware wallets or specific keys)
     *      - MNEMONIC: BIP-39 mnemonic phrase to derive the broadcaster address from
     *
     *      To use in your terminal:
     *      ```
     *      # Option 1: Direct address
     *      ETH_FROM=0x... forge script script/Deploy.s.sol --broadcast
     *
     *      # Option 2: Mnemonic derivation
     *      MNEMONIC="your twelve word phrase here" forge script script/Deploy.s.sol --broadcast
     *      ```
     */
    constructor() {
        address from = vm.envOr({ name: "ETH_FROM", defaultValue: address(0) });
        if (from != address(0)) {
            broadcaster = from;
        } else {
            mnemonic = vm.envOr({ name: "MNEMONIC", defaultValue: TEST_MNEMONIC });
            (broadcaster,) = deriveRememberKey({ mnemonic: mnemonic, index: 0 });
        }
    }

    // ============================================
    // Modifiers
    // ============================================

    /**
     * @notice Wraps function execution in a broadcast context
     * @dev This modifier uses Foundry's vm.startBroadcast/stopBroadcast to execute transactions
     *      on-chain using the configured broadcaster address. All state-changing calls within
     *      the modified function will be broadcast as transactions.
     *
     *      Usage:
     *      ```solidity
     *      function run() public broadcast returns (MyContract) {
     *          return new MyContract();
     *      }
     *      ```
     */
    modifier broadcast() {
        vm.startBroadcast(broadcaster);
        _;
        vm.stopBroadcast();
    }
}
