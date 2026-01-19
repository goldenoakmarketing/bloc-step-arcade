// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StakingPool} from "../src/StakingPool.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract StakingPoolTest is Test {
    StakingPool public stakingPool;
    MockERC20 public blocToken;

    address public owner = makeAddr("owner");
    address public vault = makeAddr("vault");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 public constant INITIAL_BALANCE = 10_000e18;

    function setUp() public {
        blocToken = new MockERC20("BLOC", "BLOC", 18);
        stakingPool = new StakingPool(address(blocToken), owner);

        // Set up vault
        vm.prank(owner);
        stakingPool.setArcadeVault(vault);

        // Distribute tokens
        blocToken.mint(alice, INITIAL_BALANCE);
        blocToken.mint(bob, INITIAL_BALANCE);
        blocToken.mint(vault, INITIAL_BALANCE);

        // Approve staking pool
        vm.prank(alice);
        blocToken.approve(address(stakingPool), type(uint256).max);

        vm.prank(bob);
        blocToken.approve(address(stakingPool), type(uint256).max);

        vm.prank(vault);
        blocToken.approve(address(stakingPool), type(uint256).max);
    }

    function test_Constructor() public view {
        assertEq(address(stakingPool.blocToken()), address(blocToken));
        assertEq(stakingPool.owner(), owner);
    }

    function test_SetArcadeVault() public {
        StakingPool newPool = new StakingPool(address(blocToken), owner);

        vm.prank(owner);
        newPool.setArcadeVault(vault);

        assertEq(newPool.arcadeVault(), vault);
    }

    function test_SetArcadeVaultOnlyOnce() public {
        StakingPool newPool = new StakingPool(address(blocToken), owner);

        vm.prank(owner);
        newPool.setArcadeVault(vault);

        vm.prank(owner);
        vm.expectRevert("StakingPool: vault already set");
        newPool.setArcadeVault(alice);
    }

    function test_Stake() public {
        uint256 stakeAmount = 1000e18;

        vm.prank(alice);
        stakingPool.stake(stakeAmount);

        assertEq(stakingPool.userStake(alice), stakeAmount);
        assertEq(stakingPool.totalStaked(), stakeAmount);
        assertEq(blocToken.balanceOf(address(stakingPool)), stakeAmount);
    }

    function test_StakeZeroReverts() public {
        vm.prank(alice);
        vm.expectRevert("StakingPool: cannot stake 0");
        stakingPool.stake(0);
    }

    function test_Unstake() public {
        uint256 stakeAmount = 1000e18;
        uint256 unstakeAmount = 400e18;

        vm.prank(alice);
        stakingPool.stake(stakeAmount);

        vm.prank(alice);
        stakingPool.unstake(unstakeAmount);

        assertEq(stakingPool.userStake(alice), stakeAmount - unstakeAmount);
        assertEq(stakingPool.totalStaked(), stakeAmount - unstakeAmount);
    }

    function test_UnstakeInsufficientReverts() public {
        uint256 stakeAmount = 1000e18;

        vm.prank(alice);
        stakingPool.stake(stakeAmount);

        vm.prank(alice);
        vm.expectRevert("StakingPool: insufficient stake");
        stakingPool.unstake(stakeAmount + 1);
    }

    function test_AddRewards() public {
        uint256 stakeAmount = 1000e18;
        uint256 rewardAmount = 100e18;

        // Alice stakes
        vm.prank(alice);
        stakingPool.stake(stakeAmount);

        // Vault adds rewards
        vm.prank(vault);
        stakingPool.addRewards(rewardAmount);

        // Check Alice's pending rewards
        uint256 pending = stakingPool.getPendingRewards(alice);
        assertEq(pending, rewardAmount);
    }

    function test_AddRewardsNoStakersReverts() public {
        vm.prank(vault);
        vm.expectRevert("StakingPool: no stakers");
        stakingPool.addRewards(100e18);
    }

    function test_ClaimRewards() public {
        uint256 stakeAmount = 1000e18;
        uint256 rewardAmount = 100e18;

        // Alice stakes
        vm.prank(alice);
        stakingPool.stake(stakeAmount);

        // Vault adds rewards
        vm.prank(vault);
        stakingPool.addRewards(rewardAmount);

        // Alice claims
        uint256 balanceBefore = blocToken.balanceOf(alice);
        vm.prank(alice);
        stakingPool.claimRewards();
        uint256 balanceAfter = blocToken.balanceOf(alice);

        assertEq(balanceAfter - balanceBefore, rewardAmount);
        assertEq(stakingPool.getPendingRewards(alice), 0);
    }

    function test_ProportionalRewards() public {
        // Alice stakes 750, Bob stakes 250 (3:1 ratio)
        vm.prank(alice);
        stakingPool.stake(750e18);

        vm.prank(bob);
        stakingPool.stake(250e18);

        // Add 100 tokens as rewards
        vm.prank(vault);
        stakingPool.addRewards(100e18);

        // Alice should get 75, Bob should get 25
        assertEq(stakingPool.getPendingRewards(alice), 75e18);
        assertEq(stakingPool.getPendingRewards(bob), 25e18);
    }

    function test_GetStakedBalance() public {
        uint256 stakeAmount = 1000e18;

        vm.prank(alice);
        stakingPool.stake(stakeAmount);

        assertEq(stakingPool.getStakedBalance(alice), stakeAmount);
    }

    function test_Earned() public {
        uint256 stakeAmount = 1000e18;
        uint256 rewardAmount = 100e18;

        vm.prank(alice);
        stakingPool.stake(stakeAmount);

        vm.prank(vault);
        stakingPool.addRewards(rewardAmount);

        assertEq(stakingPool.earned(alice), rewardAmount);
    }

    function test_OnlyVaultCanAddRewards() public {
        vm.prank(alice);
        stakingPool.stake(1000e18);

        vm.prank(alice);
        vm.expectRevert("StakingPool: caller is not vault");
        stakingPool.addRewards(100e18);
    }

    function testFuzz_Stake(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_BALANCE);

        vm.prank(alice);
        stakingPool.stake(amount);

        assertEq(stakingPool.userStake(alice), amount);
    }
}
