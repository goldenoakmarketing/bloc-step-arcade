// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IStakingPool} from "./interfaces/IStakingPool.sol";

/**
 * @title StakingPool
 * @notice In-app staking with proportional rewards using reward-per-token accounting
 * @dev Based on the Synthetix staking rewards pattern
 */
contract StakingPool is IStakingPool, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable blocToken;

    uint256 public override totalStaked;
    uint256 public rewardPerTokenStored;

    mapping(address => uint256) public userStake;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    address public arcadeVault;

    modifier onlyVault() {
        require(msg.sender == arcadeVault, "StakingPool: caller is not vault");
        _;
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    constructor(address _blocToken, address _owner) Ownable(_owner) {
        require(_blocToken != address(0), "StakingPool: zero address");
        blocToken = IERC20(_blocToken);
    }

    /**
     * @notice Set the arcade vault address (can only be set once)
     * @param _arcadeVault The address of the ArcadeVault contract
     */
    function setArcadeVault(address _arcadeVault) external onlyOwner {
        require(arcadeVault == address(0), "StakingPool: vault already set");
        require(_arcadeVault != address(0), "StakingPool: zero address");
        arcadeVault = _arcadeVault;
    }

    /**
     * @notice Stake $BLOC tokens
     * @param amount Amount of tokens to stake
     */
    function stake(uint256 amount) external override nonReentrant updateReward(msg.sender) {
        require(amount > 0, "StakingPool: cannot stake 0");

        totalStaked += amount;
        userStake[msg.sender] += amount;

        blocToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount, block.timestamp);
    }

    /**
     * @notice Unstake $BLOC tokens
     * @param amount Amount of tokens to unstake
     */
    function unstake(uint256 amount) external override nonReentrant updateReward(msg.sender) {
        require(amount > 0, "StakingPool: cannot unstake 0");
        require(userStake[msg.sender] >= amount, "StakingPool: insufficient stake");

        totalStaked -= amount;
        userStake[msg.sender] -= amount;

        blocToken.safeTransfer(msg.sender, amount);

        emit Unstaked(msg.sender, amount, block.timestamp);
    }

    /**
     * @notice Claim accumulated rewards
     */
    function claimRewards() external override nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            blocToken.safeTransfer(msg.sender, reward);

            emit RewardsClaimed(msg.sender, reward, block.timestamp);
        }
    }

    /**
     * @notice Add rewards to the pool (called by ArcadeVault)
     * @param amount Amount of rewards to add
     */
    function addRewards(uint256 amount) external override onlyVault updateReward(address(0)) {
        require(amount > 0, "StakingPool: cannot add 0 rewards");
        require(totalStaked > 0, "StakingPool: no stakers");

        blocToken.safeTransferFrom(msg.sender, address(this), amount);

        // Increase reward per token
        rewardPerTokenStored += (amount * 1e18) / totalStaked;

        emit RewardsAdded(amount, block.timestamp);
    }

    /**
     * @notice Get the staked balance of a user
     * @param user Address of the user
     * @return Staked amount
     */
    function getStakedBalance(address user) external view override returns (uint256) {
        return userStake[user];
    }

    /**
     * @notice Get pending rewards for a user
     * @param user Address of the user
     * @return Pending reward amount
     */
    function getPendingRewards(address user) external view override returns (uint256) {
        return earned(user);
    }

    /**
     * @notice Calculate current earnings for a user
     * @param account Address of the user
     * @return Current earned rewards
     */
    function earned(address account) public view override returns (uint256) {
        return
            ((userStake[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18) + rewards[account];
    }

    /**
     * @notice Get current reward per token
     * @return Current reward per token value
     */
    function rewardPerToken() public view returns (uint256) {
        return rewardPerTokenStored;
    }
}
