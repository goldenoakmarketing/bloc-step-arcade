// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IStakingPool {
    // Events
    event Staked(address indexed user, uint256 amount, uint256 timestamp);
    event Unstaked(address indexed user, uint256 amount, uint256 timestamp);
    event RewardsClaimed(address indexed user, uint256 amount, uint256 timestamp);
    event RewardsAdded(uint256 amount, uint256 timestamp);

    // Functions
    function stake(uint256 amount) external;
    function unstake(uint256 amount) external;
    function claimRewards() external;
    function addRewards(uint256 amount) external;
    function getStakedBalance(address user) external view returns (uint256);
    function getPendingRewards(address user) external view returns (uint256);
    function earned(address user) external view returns (uint256);
    function totalStaked() external view returns (uint256);
}
