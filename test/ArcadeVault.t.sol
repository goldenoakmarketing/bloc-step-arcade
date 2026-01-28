// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ArcadeVault} from "../src/ArcadeVault.sol";
import {IArcadeVault} from "../src/interfaces/IArcadeVault.sol";
import {StakingPool} from "../src/StakingPool.sol";
import {StabilityReserve} from "../src/StabilityReserve.sol";
import {YeetEngine} from "../src/YeetEngine.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockPriceFeed} from "./mocks/MockPriceFeed.sol";

contract ArcadeVaultTest is Test {
    // Local event definition for testing
    event YeetTriggered(address indexed yeeter, uint8 quarterNumber, uint256 timestamp);

    ArcadeVault public arcadeVault;
    StakingPool public stakingPool;
    StabilityReserve public stabilityReserve;
    YeetEngine public yeetEngine;
    MockERC20 public blocToken;
    MockPriceFeed public priceFeed;

    address public owner = makeAddr("owner");
    address public gameServer = makeAddr("gameServer");
    address public profitWallet = makeAddr("profitWallet");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 public constant INITIAL_BALANCE = 100_000e18;
    uint256 public constant QUARTER_AMOUNT = 250e18;
    uint256 public constant QUARTER_DURATION = 900; // 15 minutes

    function setUp() public {
        blocToken = new MockERC20("BLOC", "BLOC", 18);
        priceFeed = new MockPriceFeed(1e8, 8);

        // Deploy all contracts
        arcadeVault = new ArcadeVault(address(blocToken), owner, profitWallet);
        stakingPool = new StakingPool(address(blocToken), owner);
        stabilityReserve = new StabilityReserve(
            address(blocToken),
            address(priceFeed),
            address(0),
            owner
        );
        yeetEngine = new YeetEngine(address(blocToken), owner);

        // Configure contracts
        vm.startPrank(owner);
        arcadeVault.setStakingPool(address(stakingPool));
        arcadeVault.setStabilityReserve(address(stabilityReserve));
        arcadeVault.setYeetEngine(address(yeetEngine));
        arcadeVault.setGameServer(gameServer);

        stakingPool.setArcadeVault(address(arcadeVault));
        stabilityReserve.setArcadeVault(address(arcadeVault));
        yeetEngine.setArcadeVault(address(arcadeVault));
        vm.stopPrank();

        // Distribute tokens
        blocToken.mint(alice, INITIAL_BALANCE);
        blocToken.mint(bob, INITIAL_BALANCE);

        // Approvals
        vm.prank(alice);
        blocToken.approve(address(arcadeVault), type(uint256).max);

        vm.prank(bob);
        blocToken.approve(address(arcadeVault), type(uint256).max);
    }

    function test_Constructor() public view {
        assertEq(address(arcadeVault.blocToken()), address(blocToken));
        assertEq(arcadeVault.owner(), owner);
        assertEq(arcadeVault.profitWallet(), profitWallet);
        assertEq(arcadeVault.quarterAmount(), QUARTER_AMOUNT);
        assertEq(arcadeVault.quarterDuration(), QUARTER_DURATION);
        assertEq(arcadeVault.yeetTrigger(), 8);
    }

    function test_BuyQuarter() public {
        vm.prank(alice);
        arcadeVault.buyQuarter();

        assertEq(arcadeVault.getTimeBalance(alice), QUARTER_DURATION);
        assertEq(arcadeVault.getUserQuarterCount(alice), 1);
        assertEq(arcadeVault.vaultBalance(), QUARTER_AMOUNT);
    }

    function test_BuyDollar() public {
        vm.prank(alice);
        arcadeVault.buyDollar();

        assertEq(arcadeVault.getTimeBalance(alice), QUARTER_DURATION * 4);
        assertEq(arcadeVault.getUserQuarterCount(alice), 4);
        assertEq(arcadeVault.vaultBalance(), QUARTER_AMOUNT * 4);
    }

    function test_BuyQuarters() public {
        uint256 count = 10;

        vm.prank(alice);
        arcadeVault.buyQuarters(count);

        assertEq(arcadeVault.getTimeBalance(alice), QUARTER_DURATION * count);
        assertEq(arcadeVault.vaultBalance(), QUARTER_AMOUNT * count);
    }

    function test_BuyQuartersZeroReverts() public {
        vm.prank(alice);
        vm.expectRevert("ArcadeVault: must buy at least one quarter");
        arcadeVault.buyQuarters(0);
    }

    function test_BuyQuartersMaxReverts() public {
        vm.prank(alice);
        vm.expectRevert("ArcadeVault: max 100 quarters per transaction");
        arcadeVault.buyQuarters(101);
    }

    function test_YeetTrigger() public {
        // Buy 8 quarters to trigger yeet
        vm.prank(alice);
        arcadeVault.buyQuarters(8);

        // Quarter count should reset to 0 after triggering yeet
        assertEq(arcadeVault.getUserQuarterCount(alice), 0);
    }

    function test_YeetTriggerEmitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit YeetTriggered(alice, 8, block.timestamp);
        arcadeVault.buyQuarters(8);
    }

    function test_ConsumeTime() public {
        vm.prank(alice);
        arcadeVault.buyQuarter();

        uint256 secondsToConsume = 300; // 5 minutes

        vm.prank(gameServer);
        arcadeVault.consumeTime(alice, secondsToConsume);

        assertEq(arcadeVault.getTimeBalance(alice), QUARTER_DURATION - secondsToConsume);
    }

    function test_ConsumeTimeInsufficientReverts() public {
        vm.prank(alice);
        arcadeVault.buyQuarter();

        vm.prank(gameServer);
        vm.expectRevert("ArcadeVault: insufficient time balance");
        arcadeVault.consumeTime(alice, QUARTER_DURATION + 1);
    }

    function test_ConsumeTimeOnlyGameServer() public {
        vm.prank(alice);
        arcadeVault.buyQuarter();

        vm.prank(alice);
        vm.expectRevert("ArcadeVault: caller is not game server");
        arcadeVault.consumeTime(alice, 100);
    }

    function test_DistributeVault() public {
        // Alice buys quarters to fill vault
        vm.prank(alice);
        arcadeVault.buyQuarters(40); // 10,000 $BLOC

        // Alice stakes some tokens in the staking pool
        vm.prank(alice);
        blocToken.approve(address(stakingPool), type(uint256).max);
        vm.prank(alice);
        stakingPool.stake(1000e18);

        // Approve arcadeVault to transfer to staking pool and stability reserve
        vm.prank(address(arcadeVault));
        blocToken.approve(address(stakingPool), type(uint256).max);
        vm.prank(address(arcadeVault));
        blocToken.approve(address(stabilityReserve), type(uint256).max);

        // Fast forward past distribution interval
        vm.warp(block.timestamp + 7 days + 1);

        uint256 vaultBefore = arcadeVault.vaultBalance();
        uint256 profitBalanceBefore = blocToken.balanceOf(profitWallet);

        vm.prank(owner);
        arcadeVault.distributeVault();

        // Vault should be empty
        assertEq(arcadeVault.vaultBalance(), 0);

        // Profit wallet should have received 15%
        uint256 expectedProfit = (vaultBefore * 1500) / 10000;
        assertEq(blocToken.balanceOf(profitWallet) - profitBalanceBefore, expectedProfit);
    }

    function test_DistributeVaultTooEarlyReverts() public {
        vm.prank(alice);
        arcadeVault.buyQuarter();

        vm.prank(owner);
        vm.expectRevert("ArcadeVault: too early");
        arcadeVault.distributeVault();
    }

    function test_DistributeVaultNothingToDistributeReverts() public {
        vm.warp(block.timestamp + 7 days + 1);

        vm.prank(owner);
        vm.expectRevert("ArcadeVault: nothing to distribute");
        arcadeVault.distributeVault();
    }

    function test_SetDistributionShares() public {
        vm.prank(owner);
        arcadeVault.setDistributionShares(5000, 2500, 2500);

        assertEq(arcadeVault.stakingShare(), 5000);
        assertEq(arcadeVault.stabilityShare(), 2500);
        assertEq(arcadeVault.profitShare(), 2500);
    }

    function test_SetDistributionSharesInvalidReverts() public {
        vm.prank(owner);
        vm.expectRevert("ArcadeVault: shares must equal 100%");
        arcadeVault.setDistributionShares(5000, 3000, 3000);
    }

    function test_GetTimeBalance() public {
        assertEq(arcadeVault.getTimeBalance(alice), 0);

        vm.prank(alice);
        arcadeVault.buyQuarter();

        assertEq(arcadeVault.getTimeBalance(alice), QUARTER_DURATION);
    }

    function test_AddEligibleUser() public {
        vm.prank(owner);
        arcadeVault.addEligibleUser(alice);

        assertTrue(yeetEngine.isEligible(alice));
    }

    function test_RemoveEligibleUser() public {
        vm.prank(owner);
        arcadeVault.addEligibleUser(alice);

        vm.prank(owner);
        arcadeVault.removeEligibleUser(alice);

        assertFalse(yeetEngine.isEligible(alice));
    }

    function test_TimeUntilNextDistribution() public {
        // Initially should be 7 days
        assertEq(arcadeVault.timeUntilNextDistribution(), 7 days);

        // After 3 days, should be 4 days
        vm.warp(block.timestamp + 3 days);
        assertEq(arcadeVault.timeUntilNextDistribution(), 4 days);

        // After 7+ days, should be 0
        vm.warp(block.timestamp + 5 days);
        assertEq(arcadeVault.timeUntilNextDistribution(), 0);
    }

    function test_EmergencyWithdrawTimelock() public {
        vm.prank(alice);
        arcadeVault.buyQuarters(10);

        uint256 ownerBalanceBefore = blocToken.balanceOf(owner);

        // Step 1: Request withdrawal
        vm.prank(owner);
        arcadeVault.requestEmergencyWithdraw(address(blocToken), 1000e18);

        // Step 2: Executing before timelock should revert
        vm.prank(owner);
        vm.expectRevert("ArcadeVault: timelock not expired");
        arcadeVault.executeEmergencyWithdraw();

        // Step 3: Fast forward past 48-hour timelock
        vm.warp(block.timestamp + 48 hours + 1);

        // Step 4: Execute withdrawal
        vm.prank(owner);
        arcadeVault.executeEmergencyWithdraw();

        assertEq(blocToken.balanceOf(owner), ownerBalanceBefore + 1000e18);
    }

    function test_CancelEmergencyWithdraw() public {
        vm.prank(alice);
        arcadeVault.buyQuarters(10);

        // Request withdrawal
        vm.prank(owner);
        arcadeVault.requestEmergencyWithdraw(address(blocToken), 1000e18);

        // Cancel it
        vm.prank(owner);
        arcadeVault.cancelEmergencyWithdraw();

        // Executing after cancel should revert
        vm.warp(block.timestamp + 48 hours + 1);
        vm.prank(owner);
        vm.expectRevert("ArcadeVault: no pending withdrawal");
        arcadeVault.executeEmergencyWithdraw();
    }

    function testFuzz_BuyQuarters(uint256 count) public {
        count = bound(count, 1, 100);

        vm.prank(alice);
        arcadeVault.buyQuarters(count);

        assertEq(arcadeVault.getTimeBalance(alice), QUARTER_DURATION * count);
        assertEq(arcadeVault.vaultBalance(), QUARTER_AMOUNT * count);
    }

    function test_MultiplePurchases() public {
        vm.prank(alice);
        arcadeVault.buyQuarter();

        vm.prank(alice);
        arcadeVault.buyQuarter();

        vm.prank(alice);
        arcadeVault.buyQuarter();

        assertEq(arcadeVault.getTimeBalance(alice), QUARTER_DURATION * 3);
        assertEq(arcadeVault.getUserQuarterCount(alice), 3);
    }
}
