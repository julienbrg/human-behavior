// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.29 <0.9.0;

import { HumanBehavior } from "../src/HumanBehavior.sol";
import { BaseScript } from "./Base.s.sol";

/**
 * @title Deploy
 * @author W3HC
 * @notice Deployment script for the HumanBehavior contract
 * @custom:security-contact julien@strat.cc
 * @dev This script deploys the HumanBehavior contract with the configured parameters.
 *      It inherits from BaseScript to handle broadcaster configuration.
 *
 *      Usage:
 *      ```bash
 *      # Dry run (simulation)
 *      forge script script/Deploy.s.sol
 *
 *      # Actual deployment
 *      forge script script/Deploy.s.sol --broadcast --rpc-url <RPC_URL> --verify
 *      ```
 *
 *      For deterministic multi-chain deployment at the same address:
 *      - Use CREATE2 with the same salt and deployer address
 *      - Ensure the same constructor parameters on all chains
 *      - Consider using a deterministic deployment proxy
 *
 *      See: https://book.getfoundry.sh/guides/scripting-with-solidity
 */
contract Deploy is BaseScript {
    /**
     * @notice Executes the deployment of the HumanBehavior contract
     * @dev Currently uses placeholder addresses for testing.
     *      IMPORTANT: Update these parameters before mainnet deployment:
     *      - _home: Set to the chain ID where the Human Passport SBT is deployed
     *      - _humanPassport: Set to the actual Human Passport SBT contract address
     *      - _verifier: Set to the deployed Groth16 verifier contract address
     *
     *      The `broadcast` modifier ensures this transaction is executed on-chain.
     *
     * @return human The deployed HumanBehavior contract instance
     */
    function run() public broadcast returns (HumanBehavior human) {
        // TODO: Replace these placeholder values with actual deployment parameters
        // Current values are for testing only
        uint256 homeChainId = 10; // Placeholder: Update to actual home chain ID (e.g., 1 for Ethereum mainnet)
        address humanPassportAddress = 0x0000000000000000000000000000000000000000; // Placeholder: Update to actual SBT
            // address
        address verifierAddress = 0x0000000000000000000000000000000000000000; // Placeholder: Update to actual verifier
            // address

        human = new HumanBehavior(homeChainId, humanPassportAddress, verifierAddress);
    }
}
