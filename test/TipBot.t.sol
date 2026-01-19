// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {TipBot} from "../src/TipBot.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract TipBotTest is Test {
    TipBot public tipBot;
    MockERC20 public blocToken;

    address public owner = makeAddr("owner");
    address public bot = makeAddr("bot");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 public constant INITIAL_BALANCE = 10_000e18;
    uint256 public constant MINIMUM_TIP = 100e18;

    function setUp() public {
        blocToken = new MockERC20("BLOC", "BLOC", 18);
        tipBot = new TipBot(address(blocToken), bot, owner);

        // Distribute tokens
        blocToken.mint(alice, INITIAL_BALANCE);
        blocToken.mint(bob, INITIAL_BALANCE);

        // Approve tip bot
        vm.prank(alice);
        blocToken.approve(address(tipBot), type(uint256).max);

        vm.prank(bob);
        blocToken.approve(address(tipBot), type(uint256).max);
    }

    function test_Constructor() public view {
        assertEq(address(tipBot.blocToken()), address(blocToken));
        assertEq(tipBot.authorizedBot(), bot);
        assertEq(tipBot.owner(), owner);
        assertEq(tipBot.dailyTipLimit(), 50);
        assertEq(tipBot.minimumTip(), MINIMUM_TIP);
    }

    function test_EnableTipping() public {
        vm.prank(alice);
        tipBot.enableTipping();

        assertTrue(tipBot.isEnabled(alice));
    }

    function test_EnableTippingAlreadyEnabledReverts() public {
        vm.prank(alice);
        tipBot.enableTipping();

        vm.prank(alice);
        vm.expectRevert("TipBot: already enabled");
        tipBot.enableTipping();
    }

    function test_DisableTipping() public {
        vm.prank(alice);
        tipBot.enableTipping();

        vm.prank(alice);
        tipBot.disableTipping();

        assertFalse(tipBot.isEnabled(alice));
    }

    function test_DisableTippingNotEnabledReverts() public {
        vm.prank(alice);
        vm.expectRevert("TipBot: not enabled");
        tipBot.disableTipping();
    }

    function test_ExecuteTip() public {
        vm.prank(alice);
        tipBot.enableTipping();

        uint256 tipAmount = 200e18;
        uint256 aliceBalanceBefore = blocToken.balanceOf(alice);
        uint256 bobBalanceBefore = blocToken.balanceOf(bob);

        vm.prank(bot);
        tipBot.executeTip(alice, bob, tipAmount);

        assertEq(blocToken.balanceOf(alice), aliceBalanceBefore - tipAmount);
        assertEq(blocToken.balanceOf(bob), bobBalanceBefore + tipAmount);
    }

    function test_ExecuteTipNotAuthorizedReverts() public {
        vm.prank(alice);
        tipBot.enableTipping();

        vm.prank(alice);
        vm.expectRevert("TipBot: caller is not authorized bot");
        tipBot.executeTip(alice, bob, 200e18);
    }

    function test_ExecuteTipNotEnabledReverts() public {
        vm.prank(bot);
        vm.expectRevert("TipBot: tipping not enabled");
        tipBot.executeTip(alice, bob, 200e18);
    }

    function test_ExecuteTipBelowMinimumReverts() public {
        vm.prank(alice);
        tipBot.enableTipping();

        vm.prank(bot);
        vm.expectRevert("TipBot: below minimum tip");
        tipBot.executeTip(alice, bob, MINIMUM_TIP - 1);
    }

    function test_ExecuteTipToSelfReverts() public {
        vm.prank(alice);
        tipBot.enableTipping();

        vm.prank(bot);
        vm.expectRevert("TipBot: cannot tip yourself");
        tipBot.executeTip(alice, alice, 200e18);
    }

    function test_DailyTipLimit() public {
        vm.prank(alice);
        tipBot.enableTipping();

        // Execute 50 tips (daily limit)
        for (uint256 i = 0; i < 50; i++) {
            vm.prank(bot);
            tipBot.executeTip(alice, bob, MINIMUM_TIP);
        }

        // 51st tip should fail
        vm.prank(bot);
        vm.expectRevert("TipBot: daily limit reached");
        tipBot.executeTip(alice, bob, MINIMUM_TIP);
    }

    function test_GetRemainingDailyTips() public {
        vm.prank(alice);
        tipBot.enableTipping();

        assertEq(tipBot.getRemainingDailyTips(alice), 50);

        // Execute 10 tips
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(bot);
            tipBot.executeTip(alice, bob, MINIMUM_TIP);
        }

        assertEq(tipBot.getRemainingDailyTips(alice), 40);
    }

    function test_DailyLimitResetsNextDay() public {
        vm.prank(alice);
        tipBot.enableTipping();

        // Execute 50 tips
        for (uint256 i = 0; i < 50; i++) {
            vm.prank(bot);
            tipBot.executeTip(alice, bob, MINIMUM_TIP);
        }

        assertEq(tipBot.getRemainingDailyTips(alice), 0);

        // Move to next day
        vm.warp(block.timestamp + 1 days);

        assertEq(tipBot.getRemainingDailyTips(alice), 50);

        // Should be able to tip again
        vm.prank(bot);
        tipBot.executeTip(alice, bob, MINIMUM_TIP);

        assertEq(tipBot.getRemainingDailyTips(alice), 49);
    }

    function test_SetAuthorizedBot() public {
        address newBot = makeAddr("newBot");

        vm.prank(owner);
        tipBot.setAuthorizedBot(newBot);

        assertEq(tipBot.authorizedBot(), newBot);
    }

    function test_SetDailyTipLimit() public {
        vm.prank(owner);
        tipBot.setDailyTipLimit(100);

        assertEq(tipBot.dailyTipLimit(), 100);
    }

    function test_SetMinimumTip() public {
        vm.prank(owner);
        tipBot.setMinimumTip(50e18);

        assertEq(tipBot.minimumTip(), 50e18);
    }

    function test_IsEnabled() public {
        assertFalse(tipBot.isEnabled(alice));

        vm.prank(alice);
        tipBot.enableTipping();

        assertTrue(tipBot.isEnabled(alice));
    }

    function test_GetDailyTipCount() public {
        vm.prank(alice);
        tipBot.enableTipping();

        assertEq(tipBot.getDailyTipCount(alice), 0);

        vm.prank(bot);
        tipBot.executeTip(alice, bob, MINIMUM_TIP);

        assertEq(tipBot.getDailyTipCount(alice), 1);
    }

    function testFuzz_ExecuteTip(uint256 amount) public {
        amount = bound(amount, MINIMUM_TIP, INITIAL_BALANCE / 2);

        vm.prank(alice);
        tipBot.enableTipping();

        uint256 aliceBalanceBefore = blocToken.balanceOf(alice);

        vm.prank(bot);
        tipBot.executeTip(alice, bob, amount);

        assertEq(blocToken.balanceOf(alice), aliceBalanceBefore - amount);
    }
}
