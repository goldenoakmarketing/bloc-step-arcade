// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IArcadeVault} from "./interfaces/IArcadeVault.sol";
import {IYeetEngine} from "./interfaces/IYeetEngine.sol";
import {IStakingPool} from "./interfaces/IStakingPool.sol";
import {IStabilityReserve} from "./interfaces/IStabilityReserve.sol";

/**
 * @title ArcadeVault
 * @notice Core contract for time purchases and vault management
 * @dev Manages arcade time purchases, yeet mechanics, and vault distribution
 */
contract ArcadeVault is IArcadeVault, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable blocToken;

    uint256 public constant override quarterAmount = 250e18; // 250 $BLOC
    uint256 public constant override quarterDuration = 900; // 15 minutes in seconds
    uint256 public constant override yeetTrigger = 8; // Every 8th quarter

    mapping(address => uint8) public userQuarterCount;
    mapping(address => uint256) public userTimeBalance;
    mapping(address => uint256) public totalYeeted;

    uint256 public override vaultBalance;
    uint256 public lastDistribution;

    IYeetEngine public yeetEngine;
    IStakingPool public stakingPool;
    IStabilityReserve public stabilityReserve;

    address public gameServer;
    address public profitWallet;

    // Distribution percentages in basis points (total = 10000)
    uint256 public stakingShare = 6000; // 60%
    uint256 public stabilityShare = 2500; // 25%
    uint256 public profitShare = 1500; // 15%

    uint256 public constant BASIS_POINTS = 10_000;
    uint256 public constant DISTRIBUTION_INTERVAL = 7 days;

    modifier onlyGameServer() {
        require(msg.sender == gameServer, "ArcadeVault: caller is not game server");
        _;
    }

    constructor(
        address _blocToken,
        address _owner,
        address _profitWallet
    ) Ownable(_owner) {
        require(_blocToken != address(0), "ArcadeVault: zero token address");
        require(_profitWallet != address(0), "ArcadeVault: zero profit wallet");

        blocToken = IERC20(_blocToken);
        profitWallet = _profitWallet;
        lastDistribution = block.timestamp;
    }

    /**
     * @notice Set the YeetEngine contract address
     * @param _yeetEngine Address of YeetEngine contract
     */
    function setYeetEngine(address _yeetEngine) external onlyOwner {
        require(_yeetEngine != address(0), "ArcadeVault: zero address");
        yeetEngine = IYeetEngine(_yeetEngine);
    }

    /**
     * @notice Set the StakingPool contract address
     * @param _stakingPool Address of StakingPool contract
     */
    function setStakingPool(address _stakingPool) external onlyOwner {
        require(_stakingPool != address(0), "ArcadeVault: zero address");
        stakingPool = IStakingPool(_stakingPool);
    }

    /**
     * @notice Set the StabilityReserve contract address
     * @param _stabilityReserve Address of StabilityReserve contract
     */
    function setStabilityReserve(address _stabilityReserve) external onlyOwner {
        require(_stabilityReserve != address(0), "ArcadeVault: zero address");
        stabilityReserve = IStabilityReserve(_stabilityReserve);
    }

    /**
     * @notice Set the game server address
     * @param _gameServer Address authorized to consume time
     */
    function setGameServer(address _gameServer) external onlyOwner {
        require(_gameServer != address(0), "ArcadeVault: zero address");
        gameServer = _gameServer;
    }

    /**
     * @notice Set the profit wallet address
     * @param _profitWallet Address to receive profit share
     */
    function setProfitWallet(address _profitWallet) external onlyOwner {
        require(_profitWallet != address(0), "ArcadeVault: zero address");
        profitWallet = _profitWallet;
    }

    /**
     * @notice Update distribution shares
     * @param _stakingShare Staking pool share in basis points
     * @param _stabilityShare Stability reserve share in basis points
     * @param _profitShare Profit wallet share in basis points
     */
    function setDistributionShares(
        uint256 _stakingShare,
        uint256 _stabilityShare,
        uint256 _profitShare
    ) external onlyOwner {
        require(
            _stakingShare + _stabilityShare + _profitShare == BASIS_POINTS,
            "ArcadeVault: shares must equal 100%"
        );

        stakingShare = _stakingShare;
        stabilityShare = _stabilityShare;
        profitShare = _profitShare;
    }

    /**
     * @notice Purchase a single quarter (15 min of play time)
     */
    function buyQuarter() external override nonReentrant {
        _buyQuarters(1);
    }

    /**
     * @notice Purchase 4 quarters (1 hour of play time) - the "dollar" package
     */
    function buyDollar() external override nonReentrant {
        _buyQuarters(4);
    }

    /**
     * @notice Purchase multiple quarters at once
     * @param count Number of quarters to purchase
     */
    function buyQuarters(uint256 count) external override nonReentrant {
        _buyQuarters(count);
    }

    /**
     * @notice Internal function to handle quarter purchases
     * @param count Number of quarters to purchase
     */
    function _buyQuarters(uint256 count) internal {
        require(count > 0, "ArcadeVault: must buy at least one quarter");
        require(count <= 100, "ArcadeVault: max 100 quarters per transaction");

        uint256 totalCost = quarterAmount * count;
        uint256 totalTime = quarterDuration * count;

        blocToken.safeTransferFrom(msg.sender, address(this), totalCost);

        vaultBalance += totalCost;
        userTimeBalance[msg.sender] += totalTime;

        // Process each quarter for yeet logic
        for (uint256 i = 0; i < count; i++) {
            userQuarterCount[msg.sender]++;

            // Check for yeet trigger
            if (userQuarterCount[msg.sender] == yeetTrigger) {
                userQuarterCount[msg.sender] = 0;
                emit YeetTriggered(msg.sender, uint8(yeetTrigger), block.timestamp);
            }
        }

        emit TimePurchased(
            msg.sender,
            count,
            totalTime,
            userTimeBalance[msg.sender],
            block.timestamp
        );
    }

    /**
     * @notice Get the remaining time balance for a user
     * @param user Address to check
     * @return Time balance in seconds
     */
    function getTimeBalance(address user) external view override returns (uint256) {
        return userTimeBalance[user];
    }

    /**
     * @notice Consume time from a player's balance (called by game server)
     * @param player Address of the player
     * @param secondsToConsume Amount of time to deduct
     */
    function consumeTime(
        address player,
        uint256 secondsToConsume
    ) external override onlyGameServer {
        require(player != address(0), "ArcadeVault: zero address");
        require(secondsToConsume > 0, "ArcadeVault: zero seconds");
        require(
            userTimeBalance[player] >= secondsToConsume,
            "ArcadeVault: insufficient time balance"
        );

        userTimeBalance[player] -= secondsToConsume;

        emit TimeConsumed(player, secondsToConsume, userTimeBalance[player], block.timestamp);
    }

    /**
     * @notice Distribute vault balance to staking, stability, and profit
     */
    function distributeVault() external override onlyOwner nonReentrant {
        require(
            block.timestamp >= lastDistribution + DISTRIBUTION_INTERVAL,
            "ArcadeVault: too early"
        );
        require(vaultBalance > 0, "ArcadeVault: nothing to distribute");

        uint256 toDistribute = vaultBalance;
        vaultBalance = 0;
        lastDistribution = block.timestamp;

        uint256 stakingAmt = (toDistribute * stakingShare) / BASIS_POINTS;
        uint256 stabilityAmt = (toDistribute * stabilityShare) / BASIS_POINTS;
        uint256 profitAmt = toDistribute - stakingAmt - stabilityAmt;

        // Transfer to staking pool
        if (stakingAmt > 0 && address(stakingPool) != address(0)) {
            blocToken.forceApprove(address(stakingPool), stakingAmt);
            stakingPool.addRewards(stakingAmt);
        }

        // Transfer to stability reserve
        if (stabilityAmt > 0 && address(stabilityReserve) != address(0)) {
            blocToken.forceApprove(address(stabilityReserve), stabilityAmt);
            stabilityReserve.deposit(stabilityAmt);
        }

        // Transfer to profit wallet
        if (profitAmt > 0) {
            blocToken.safeTransfer(profitWallet, profitAmt);
        }

        emit VaultDistributed(stakingAmt, stabilityAmt, profitAmt, block.timestamp);
    }

    /**
     * @notice Get user's current quarter count
     * @param user Address to check
     * @return Current quarter count (resets at yeetTrigger)
     */
    function getUserQuarterCount(address user) external view override returns (uint8) {
        return userQuarterCount[user];
    }

    /**
     * @notice Get total amount yeeted by a user
     * @param user Address to check
     * @return Total yeeted amount
     */
    function getTotalYeeted(address user) external view override returns (uint256) {
        return totalYeeted[user];
    }

    /**
     * @notice Add a user to the eligible yeet pool
     * @param user Address to add
     */
    function addEligibleUser(address user) external onlyOwner {
        require(address(yeetEngine) != address(0), "ArcadeVault: yeet engine not set");
        yeetEngine.addEligibleUser(user);
    }

    /**
     * @notice Remove a user from the eligible yeet pool
     * @param user Address to remove
     */
    function removeEligibleUser(address user) external onlyOwner {
        require(address(yeetEngine) != address(0), "ArcadeVault: yeet engine not set");
        yeetEngine.removeEligibleUser(user);
    }

    /**
     * @notice Execute a yeet from one user to another
     * @param from Sender address
     * @param to Recipient address
     * @param amount Amount to yeet
     */
    function executeYeet(
        address from,
        address to,
        uint256 amount
    ) external onlyOwner {
        require(address(yeetEngine) != address(0), "ArcadeVault: yeet engine not set");

        totalYeeted[from] += amount;
        yeetEngine.executeYeet(from, to, amount);
    }

    /**
     * @notice Get time until next distribution is allowed
     * @return Seconds until next distribution (0 if ready)
     */
    function timeUntilNextDistribution() external view returns (uint256) {
        uint256 nextDistribution = lastDistribution + DISTRIBUTION_INTERVAL;
        if (block.timestamp >= nextDistribution) {
            return 0;
        }
        return nextDistribution - block.timestamp;
    }

    /**
     * @notice Emergency withdraw function
     * @param token Token to withdraw
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            payable(owner()).transfer(amount);
        } else {
            IERC20(token).safeTransfer(owner(), amount);
        }
    }
}
