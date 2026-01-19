// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StabilityReserve} from "../src/StabilityReserve.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockPriceFeed} from "./mocks/MockPriceFeed.sol";

contract StabilityReserveTest is Test {
    StabilityReserve public stabilityReserve;
    MockERC20 public blocToken;
    MockPriceFeed public priceFeed;

    address public owner = makeAddr("owner");
    address public vault = makeAddr("vault");
    address public alice = makeAddr("alice");

    uint256 public constant INITIAL_BALANCE = 10_000e18;
    int256 public constant INITIAL_PRICE = 1e8; // $1.00 with 8 decimals

    function setUp() public {
        blocToken = new MockERC20("BLOC", "BLOC", 18);
        priceFeed = new MockPriceFeed(INITIAL_PRICE, 8);

        stabilityReserve = new StabilityReserve(
            address(blocToken),
            address(priceFeed),
            address(0), // No router for tests
            owner
        );

        // Set up vault
        vm.prank(owner);
        stabilityReserve.setArcadeVault(vault);

        // Distribute tokens
        blocToken.mint(vault, INITIAL_BALANCE);

        vm.prank(vault);
        blocToken.approve(address(stabilityReserve), type(uint256).max);
    }

    function test_Constructor() public view {
        assertEq(address(stabilityReserve.blocToken()), address(blocToken));
        assertEq(address(stabilityReserve.priceFeed()), address(priceFeed));
        assertEq(stabilityReserve.owner(), owner);
        assertEq(stabilityReserve.priceThreshold(), 1000); // 10%
    }

    function test_SetArcadeVault() public {
        StabilityReserve newReserve = new StabilityReserve(
            address(blocToken),
            address(priceFeed),
            address(0),
            owner
        );

        vm.prank(owner);
        newReserve.setArcadeVault(vault);

        assertEq(newReserve.arcadeVault(), vault);
    }

    function test_Deposit() public {
        uint256 amount = 1000e18;

        vm.prank(vault);
        stabilityReserve.deposit(amount);

        assertEq(stabilityReserve.reserveBalance(), amount);
        assertEq(stabilityReserve.getReserveBalance(), amount);
    }

    function test_DepositZeroReverts() public {
        vm.prank(vault);
        vm.expectRevert("StabilityReserve: zero amount");
        stabilityReserve.deposit(0);
    }

    function test_DepositOnlyVault() public {
        vm.prank(alice);
        vm.expectRevert("StabilityReserve: caller is not vault");
        stabilityReserve.deposit(1000e18);
    }

    function test_CheckPrice() public view {
        uint256 price = stabilityReserve.checkPrice();
        assertEq(price, uint256(INITIAL_PRICE));
    }

    function test_CheckPriceStaleReverts() public {
        // Move time forward past staleness threshold
        vm.warp(block.timestamp + 2 hours);

        vm.expectRevert("StabilityReserve: stale price");
        stabilityReserve.checkPrice();
    }

    function test_UpdatePriceThreshold() public {
        uint256 newThreshold = 2000; // 20%

        vm.prank(owner);
        stabilityReserve.updatePriceThreshold(newThreshold);

        assertEq(stabilityReserve.priceThreshold(), newThreshold);
    }

    function test_UpdatePriceThresholdInvalidReverts() public {
        vm.prank(owner);
        vm.expectRevert("StabilityReserve: invalid threshold");
        stabilityReserve.updatePriceThreshold(6000); // Above 50% max
    }

    function test_UpdatePriceThresholdOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        stabilityReserve.updatePriceThreshold(2000);
    }

    function test_SetPriceFeed() public {
        MockPriceFeed newFeed = new MockPriceFeed(2e8, 8);

        vm.prank(owner);
        stabilityReserve.setPriceFeed(address(newFeed));

        assertEq(address(stabilityReserve.priceFeed()), address(newFeed));
        assertEq(stabilityReserve.lastPrice(), 2e8);
    }

    function test_UpdateLastPrice() public {
        // Change the price
        priceFeed.setPrice(0.95e8);

        vm.prank(owner);
        stabilityReserve.updateLastPrice();

        assertEq(stabilityReserve.lastPrice(), 0.95e8);
    }

    function test_EmergencyWithdraw() public {
        // Deposit some tokens
        vm.prank(vault);
        stabilityReserve.deposit(1000e18);

        uint256 ownerBalanceBefore = blocToken.balanceOf(owner);

        vm.prank(owner);
        stabilityReserve.emergencyWithdraw(address(blocToken), 500e18);

        assertEq(blocToken.balanceOf(owner), ownerBalanceBefore + 500e18);
    }

    function test_LastPrice() public view {
        assertEq(stabilityReserve.lastPrice(), uint256(INITIAL_PRICE));
    }

    function test_GetReserveBalance() public {
        vm.prank(vault);
        stabilityReserve.deposit(500e18);

        assertEq(stabilityReserve.getReserveBalance(), 500e18);
    }

    function testFuzz_Deposit(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_BALANCE);

        vm.prank(vault);
        stabilityReserve.deposit(amount);

        assertEq(stabilityReserve.reserveBalance(), amount);
    }
}
