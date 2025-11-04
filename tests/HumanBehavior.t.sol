// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.29 <0.9.0;

import { Test } from "forge-std/src/Test.sol";
import { console2 } from "forge-std/src/console2.sol";
import { HumanBehavior } from "../src/HumanBehavior.sol";
import { MockERC721 } from "../src/mocks/MockERC721.sol";
import { MockGroth16Verifier } from "../src/mocks/MockGroth16Verifier.sol";

contract HumanBehaviorTest is Test {
    HumanBehavior public humanBehavior;
    MockERC721 public mockSBT;
    MockGroth16Verifier public mockVerifier;

    address public owner;
    address public human1;
    address public human2;
    address public nonHuman;
    address public relayer;

    uint256 constant HOME_CHAIN_ID = 1;
    uint256 constant FOREIGN_CHAIN_ID = 42;

    // ERC-5564 stealth meta-address: 66 bytes = 33 bytes spending pubkey + 33 bytes viewing pubkey
    // Each compressed pubkey starts with 0x02 or 0x03
    bytes public constant VALID_STEALTH_META_ADDRESS = bytes(
        hex"02aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa03bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    );
    bytes public constant VALID_STEALTH_META_ADDRESS_2 = bytes(
        hex"02cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc03dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
    );

    function setUp() public {
        // Set the chain ID to HOME_CHAIN_ID for all tests by default
        vm.chainId(HOME_CHAIN_ID);

        owner = address(0x1);
        human1 = vm.addr(human1Key());
        human2 = vm.addr(human2Key());
        nonHuman = vm.addr(nonHumanKey());
        relayer = address(0x5);

        vm.startPrank(owner);
        mockSBT = new MockERC721("HumanPassport", "HP");
        mockVerifier = new MockGroth16Verifier();
        mockVerifier.setDefaultResult(true); // By default, accept all proofs for testing
        humanBehavior = new HumanBehavior(HOME_CHAIN_ID, address(mockSBT), address(mockVerifier));
        vm.stopPrank();

        // Mint SBTs to humans
        vm.prank(address(mockSBT)); // Mock minting
        mockSBT.mint(human1);
        vm.prank(address(mockSBT));
        mockSBT.mint(human2);
    }

    // --- Constructor Tests ---
    function testConstructor_SetsCorrectValues() public view {
        assertEq(humanBehavior.HOME(), HOME_CHAIN_ID);
        assertEq(humanBehavior.HUMAN_PASSPORT(), address(mockSBT));
        assertEq(address(humanBehavior.VERIFIER()), address(mockVerifier));
    }

    function testConstructor_RevertsOnZeroSBTAddress() public {
        vm.expectRevert(HumanBehavior.InvalidSBTAddress.selector);
        new HumanBehavior(HOME_CHAIN_ID, address(0), address(mockVerifier));
    }

    function testConstructor_RevertsOnZeroVerifierAddress() public {
        vm.expectRevert(HumanBehavior.ZeroAddressNotAllowed.selector);
        new HumanBehavior(HOME_CHAIN_ID, address(mockSBT), address(0));
    }

    // --- link Tests ---
    function testlink_Success() public {
        // Expect the event to be emitted
        vm.startPrank(human1);
        vm.expectEmit(true, true, false, false);
        bytes32 expectedHash = keccak256(VALID_STEALTH_META_ADDRESS);
        emit HumanBehavior.StealthMetaAddressLinked(expectedHash, human1);
        humanBehavior.link(VALID_STEALTH_META_ADDRESS);
        vm.stopPrank();

        // Verify state changes
        bytes32 metaAddressHash = keccak256(VALID_STEALTH_META_ADDRESS);
        assertTrue(humanBehavior.isHumanMetaAddress(metaAddressHash));
        assertTrue(humanBehavior.hasLinked(human1));
    }

    function testlink_RevertsOnWrongChain() public {
        vm.chainId(FOREIGN_CHAIN_ID);
        vm.prank(human1);
        vm.expectRevert(HumanBehavior.ProofsOnlyOnHomeChain.selector);
        humanBehavior.link(VALID_STEALTH_META_ADDRESS);
    }

    function testlink_RevertsOnInvalidLength() public {
        vm.prank(human1);
        vm.expectRevert(HumanBehavior.InvalidStealthMetaAddressLength.selector);
        humanBehavior.link(bytes("invalid"));
    }

    function testlink_RevertsIfAlreadyLinked() public {
        vm.startPrank(human1);
        humanBehavior.link(VALID_STEALTH_META_ADDRESS);

        vm.expectRevert(HumanBehavior.AlreadyLinked.selector);
        humanBehavior.link(VALID_STEALTH_META_ADDRESS_2);
        vm.stopPrank();
    }

    function testlink_RevertsIfNotHuman() public {
        vm.prank(nonHuman);
        vm.expectRevert(HumanBehavior.NotVerifiedHumanOnHomeChain.selector);
        humanBehavior.link(VALID_STEALTH_META_ADDRESS);
    }

    // --- claim Tests (with zkSNARK proofs) ---
    function testclaim_Success() public {
        // Setup: Link meta address on home chain
        vm.startPrank(human1);
        humanBehavior.link(VALID_STEALTH_META_ADDRESS);
        vm.stopPrank();

        address stealthAddress = address(0x1234);
        bytes32 metaHash = keccak256(VALID_STEALTH_META_ADDRESS);

        // Create a mock zkSNARK proof (in real scenario, this would be generated off-chain)
        bytes memory zkProof = hex"1234567890abcdef"; // Mock proof

        // Switch to foreign chain and claim
        vm.chainId(FOREIGN_CHAIN_ID);

        // Expect the event to be emitted on the foreign chain
        vm.prank(relayer);
        vm.expectEmit(true, true, false, false);
        emit HumanBehavior.HumanStatusClaimed(stealthAddress, metaHash);
        humanBehavior.claim(stealthAddress, metaHash, zkProof);

        assertTrue(humanBehavior.isHuman(stealthAddress));
    }

    function testclaim_SuccessOnHomeChain() public {
        // Verify claiming also works on the home chain (not just foreign chains)
        vm.startPrank(human1);
        humanBehavior.link(VALID_STEALTH_META_ADDRESS);
        vm.stopPrank();

        address stealthAddress = address(0x5678);
        bytes32 metaHash = keccak256(VALID_STEALTH_META_ADDRESS);
        bytes memory zkProof = hex"abcdef1234567890";

        vm.prank(relayer);
        vm.expectEmit(true, true, false, false);
        emit HumanBehavior.HumanStatusClaimed(stealthAddress, metaHash);
        humanBehavior.claim(stealthAddress, metaHash, zkProof);

        assertTrue(humanBehavior.isHuman(stealthAddress));
    }

    function testclaim_RevertsOnInvalidProof() public {
        // Link meta address
        vm.startPrank(human1);
        humanBehavior.link(VALID_STEALTH_META_ADDRESS);
        vm.stopPrank();

        address stealthAddress = address(0x1234);
        bytes32 metaHash = keccak256(VALID_STEALTH_META_ADDRESS);
        bytes memory invalidZkProof = hex"deadbeef";

        // Configure mock verifier to reject this specific proof
        uint256[] memory publicInputs = new uint256[](2);
        publicInputs[0] = uint256(uint160(stealthAddress));
        publicInputs[1] = uint256(metaHash);
        mockVerifier.setProofResult(invalidZkProof, publicInputs, false);

        vm.chainId(FOREIGN_CHAIN_ID);
        vm.prank(relayer);
        vm.expectRevert(HumanBehavior.InvalidHumanStatusProof.selector);
        humanBehavior.claim(stealthAddress, metaHash, invalidZkProof);
    }

    function testclaim_RevertsOnZeroAddress() public {
        vm.startPrank(human1);
        humanBehavior.link(VALID_STEALTH_META_ADDRESS);
        vm.stopPrank();

        bytes32 metaHash = keccak256(VALID_STEALTH_META_ADDRESS);
        bytes memory zkProof = hex"1234567890abcdef";

        vm.chainId(FOREIGN_CHAIN_ID);
        vm.prank(relayer);
        vm.expectRevert(HumanBehavior.ZeroAddressNotAllowed.selector);
        humanBehavior.claim(address(0), metaHash, zkProof);
    }

    function testclaim_RevertsOnUnlinkedMetaAddressHash() public {
        address stealthAddress = address(0x1234);
        bytes32 fakeMetaHash = keccak256("fake_meta_address");
        bytes memory zkProof = hex"1234567890abcdef";

        vm.chainId(FOREIGN_CHAIN_ID);
        vm.prank(relayer);
        vm.expectRevert(HumanBehavior.InvalidHumanStatusProof.selector);
        humanBehavior.claim(stealthAddress, fakeMetaHash, zkProof);
    }

    // --- View Function Tests ---
    function testIsHumanMetaAddressOnChain() public {
        vm.startPrank(human1);
        humanBehavior.link(VALID_STEALTH_META_ADDRESS);
        vm.stopPrank();

        assertTrue(humanBehavior.isHumanMetaAddressOnChain(VALID_STEALTH_META_ADDRESS));
        assertFalse(humanBehavior.isHumanMetaAddressOnChain(VALID_STEALTH_META_ADDRESS_2));
    }

    function testIsHumanOnChain() public {
        // Initially false
        assertFalse(humanBehavior.isHumanOnChain(address(0x1234)));

        // After claiming on foreign chain (test this scenario)
        vm.chainId(FOREIGN_CHAIN_ID);
        vm.prank(relayer);
        // This would require a valid proof, so we'll just test the getter
        // The actual claiming is tested in claim_Success
    }

    // --- Helper Functions ---
    function human1Key() internal pure returns (uint256) {
        return 0xa11ce; // Private key for human1 in test environment
    }

    function human2Key() internal pure returns (uint256) {
        return 0xb0b; // Private key for human2 in test environment
    }

    function nonHumanKey() internal pure returns (uint256) {
        return 0xbad; // Private key for nonHuman in test environment
    }
}
