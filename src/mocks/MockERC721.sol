// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.29 <0.9.0;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/**
 * @title MockERC721
 * @author W3HC
 * @notice Mock ERC721 token for testing purposes
 * @custom:security-contact julien@strat.cc
 * @dev This contract provides a simple ERC721 implementation with public minting functionality.
 *      Used in tests to simulate Human Passport SBT contracts without requiring complex verification logic.
 *
 *      WARNING: This is a mock contract for testing only. Do NOT use in production.
 */
contract MockERC721 is ERC721 {
    /// @dev Counter for generating unique token IDs
    uint256 private _nextTokenId;

    /**
     * @notice Initializes the mock ERC721 token with a name and symbol
     * @param name The name of the token collection
     * @param symbol The symbol of the token collection
     */
    constructor(string memory name, string memory symbol) ERC721(name, symbol) { }

    /**
     * @notice Mints a new token to the specified address
     * @dev This function is intentionally permissionless for testing purposes.
     *      In production, minting should be restricted by access control or verification logic.
     *
     * @param to The address that will receive the newly minted token
     */
    function mint(address to) external {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
    }
}
