// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {YeetEngine} from "../src/YeetEngine.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract YeetEngineTest is Test {
    YeetEngine public yeetEngine;
    MockERC20 public blocToken;

    address public owner = makeAddr("owner");
    address public vault = makeAddr("vault");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    uint256 public constant INITIAL_BALANCE = 10_000e18;

    function setUp() public {
        blocToken = new MockERC20("BLOC", "BLOC", 18);
        yeetEngine = new YeetEngine(address(blocToken), owner);

        // Set up vault
        vm.prank(owner);
        yeetEngine.setArcadeVault(vault);

        // Distribute tokens
        blocToken.mint(alice, INITIAL_BALANCE);
        blocToken.mint(bob, INITIAL_BALANCE);
        blocToken.mint(charlie, INITIAL_BALANCE);

        // Approve yeet engine
        vm.prank(alice);
        blocToken.approve(address(yeetEngine), type(uint256).max);

        vm.prank(bob);
        blocToken.approve(address(yeetEngine), type(uint256).max);
    }

    function test_Constructor() public view {
        assertEq(address(yeetEngine.blocToken()), address(blocToken));
        assertEq(yeetEngine.owner(), owner);
    }

    function test_SetArcadeVault() public {
        YeetEngine newEngine = new YeetEngine(address(blocToken), owner);

        vm.prank(owner);
        newEngine.setArcadeVault(vault);

        assertEq(newEngine.arcadeVault(), vault);
    }

    function test_AddEligibleUser() public {
        vm.prank(vault);
        yeetEngine.addEligibleUser(alice);

        assertTrue(yeetEngine.isEligible(alice));
        assertEq(yeetEngine.getEligibleUsersCount(), 1);
    }

    function test_AddEligibleUserAlreadyEligibleReverts() public {
        vm.prank(vault);
        yeetEngine.addEligibleUser(alice);

        vm.prank(vault);
        vm.expectRevert("YeetEngine: already eligible");
        yeetEngine.addEligibleUser(alice);
    }

    function test_RemoveEligibleUser() public {
        vm.prank(vault);
        yeetEngine.addEligibleUser(alice);

        vm.prank(vault);
        yeetEngine.addEligibleUser(bob);

        vm.prank(vault);
        yeetEngine.removeEligibleUser(alice);

        assertFalse(yeetEngine.isEligible(alice));
        assertTrue(yeetEngine.isEligible(bob));
        assertEq(yeetEngine.getEligibleUsersCount(), 1);
    }

    function test_RemoveEligibleUserNotEligibleReverts() public {
        vm.prank(vault);
        vm.expectRevert("YeetEngine: not eligible");
        yeetEngine.removeEligibleUser(alice);
    }

    function test_Commit() public {
        bytes32 secret = keccak256("mysecret");
        bytes32 hash = keccak256(abi.encodePacked(secret, alice));

        vm.prank(alice);
        yeetEngine.commit(hash);

        assertEq(yeetEngine.commits(alice), hash);
        assertEq(yeetEngine.commitBlock(alice), block.number);
    }

    function test_CommitInvalidHashReverts() public {
        vm.prank(alice);
        vm.expectRevert("YeetEngine: invalid hash");
        yeetEngine.commit(bytes32(0));
    }

    function test_Reveal() public {
        // Add eligible users
        vm.prank(vault);
        yeetEngine.addEligibleUser(bob);

        vm.prank(vault);
        yeetEngine.addEligibleUser(charlie);

        // Alice commits
        bytes32 secret = keccak256("mysecret");
        bytes32 hash = keccak256(abi.encodePacked(secret, alice));

        vm.prank(alice);
        yeetEngine.commit(hash);

        // Move forward by 2 blocks
        vm.roll(block.number + 2);

        // Alice reveals
        vm.prank(alice);
        address recipient = yeetEngine.reveal(secret);

        // Recipient should be one of the eligible users
        assertTrue(recipient == bob || recipient == charlie);

        // Commit should be cleared
        assertEq(yeetEngine.commits(alice), bytes32(0));
    }

    function test_RevealNoCommitReverts() public {
        bytes32 secret = keccak256("mysecret");

        vm.prank(alice);
        vm.expectRevert("YeetEngine: no commit found");
        yeetEngine.reveal(secret);
    }

    function test_RevealTooEarlyReverts() public {
        bytes32 secret = keccak256("mysecret");
        bytes32 hash = keccak256(abi.encodePacked(secret, alice));

        vm.prank(alice);
        yeetEngine.commit(hash);

        // Try to reveal in same block
        vm.prank(alice);
        vm.expectRevert("YeetEngine: reveal too early");
        yeetEngine.reveal(secret);
    }

    function test_RevealInvalidSecretReverts() public {
        vm.prank(vault);
        yeetEngine.addEligibleUser(bob);

        bytes32 secret = keccak256("mysecret");
        bytes32 wrongSecret = keccak256("wrongsecret");
        bytes32 hash = keccak256(abi.encodePacked(secret, alice));

        vm.prank(alice);
        yeetEngine.commit(hash);

        vm.roll(block.number + 2);

        vm.prank(alice);
        vm.expectRevert("YeetEngine: invalid reveal");
        yeetEngine.reveal(wrongSecret);
    }

    function test_ExecuteYeet() public {
        uint256 amount = 100e18;

        vm.prank(vault);
        yeetEngine.executeYeet(alice, bob, amount);

        assertEq(yeetEngine.leaderboard(alice), amount);
        assertEq(blocToken.balanceOf(bob), INITIAL_BALANCE + amount);
        assertEq(blocToken.balanceOf(alice), INITIAL_BALANCE - amount);
    }

    function test_ExecuteYeetOnlyVault() public {
        vm.prank(alice);
        vm.expectRevert("YeetEngine: caller is not vault");
        yeetEngine.executeYeet(alice, bob, 100e18);
    }

    function test_GetLeaderboard() public {
        // Add eligible users
        vm.prank(vault);
        yeetEngine.addEligibleUser(alice);

        vm.prank(vault);
        yeetEngine.addEligibleUser(bob);

        // Execute yeets to build leaderboard
        vm.prank(vault);
        yeetEngine.executeYeet(alice, charlie, 200e18);

        vm.prank(vault);
        yeetEngine.executeYeet(bob, charlie, 100e18);

        (address[] memory addresses, uint256[] memory amounts) = yeetEngine.getLeaderboard();

        assertEq(addresses[0], alice);
        assertEq(amounts[0], 200e18);
        assertEq(addresses[1], bob);
        assertEq(amounts[1], 100e18);
    }

    function test_GetYeetedAmount() public {
        vm.prank(vault);
        yeetEngine.executeYeet(alice, bob, 100e18);

        assertEq(yeetEngine.getYeetedAmount(alice), 100e18);
    }

    function test_OnlyVaultCanAddEligibleUser() public {
        vm.prank(alice);
        vm.expectRevert("YeetEngine: caller is not vault");
        yeetEngine.addEligibleUser(bob);
    }
}
