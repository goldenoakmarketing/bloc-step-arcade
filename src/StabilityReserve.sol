// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IStabilityReserve} from "./interfaces/IStabilityReserve.sol";

/**
 * @title AggregatorV3Interface
 * @notice Chainlink price feed interface
 */
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function version() external view returns (uint256);
    function getRoundData(uint80 _roundId)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/**
 * @title IUniswapV2Router
 * @notice Minimal interface for Uniswap V2 style router for buybacks
 */
interface IUniswapV2Router {
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function WETH() external pure returns (address);
}

/**
 * @title StabilityReserve
 * @notice Price oracle and buyback mechanism for $BLOC token
 * @dev Uses Chainlink price feeds and executes buybacks when price drops
 */
contract StabilityReserve is IStabilityReserve, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable blocToken;
    AggregatorV3Interface public priceFeed;
    IUniswapV2Router public router;

    uint256 public reserveBalance;
    uint256 public override lastPrice;
    uint256 public override priceThreshold; // In basis points (1000 = 10%)

    address public arcadeVault;

    uint256 public constant BASIS_POINTS = 10_000;
    uint256 public constant MAX_THRESHOLD = 5000; // 50% max threshold
    uint256 public constant PRICE_STALENESS = 1 hours;

    modifier onlyVault() {
        require(msg.sender == arcadeVault, "StabilityReserve: caller is not vault");
        _;
    }

    constructor(
        address _blocToken,
        address _priceFeed,
        address _router,
        address _owner
    ) Ownable(_owner) {
        require(_blocToken != address(0), "StabilityReserve: zero token address");

        blocToken = IERC20(_blocToken);
        priceThreshold = 1000; // Default 10%

        if (_priceFeed != address(0)) {
            priceFeed = AggregatorV3Interface(_priceFeed);
            lastPrice = checkPrice();
        }

        if (_router != address(0)) {
            router = IUniswapV2Router(_router);
        }
    }

    /**
     * @notice Set the arcade vault address (can only be set once)
     * @param _arcadeVault The address of the ArcadeVault contract
     */
    function setArcadeVault(address _arcadeVault) external onlyOwner {
        require(arcadeVault == address(0), "StabilityReserve: vault already set");
        require(_arcadeVault != address(0), "StabilityReserve: zero address");
        arcadeVault = _arcadeVault;
    }

    /**
     * @notice Set the price feed address
     * @param _priceFeed The Chainlink price feed address
     */
    function setPriceFeed(address _priceFeed) external onlyOwner {
        require(_priceFeed != address(0), "StabilityReserve: zero address");
        priceFeed = AggregatorV3Interface(_priceFeed);
        lastPrice = checkPrice();
    }

    /**
     * @notice Set the router address for buybacks
     * @param _router The DEX router address
     */
    function setRouter(address _router) external onlyOwner {
        require(_router != address(0), "StabilityReserve: zero address");
        router = IUniswapV2Router(_router);
    }

    /**
     * @notice Deposit tokens to the reserve (called by ArcadeVault)
     * @param amount Amount of tokens to deposit
     */
    function deposit(uint256 amount) external override onlyVault {
        require(amount > 0, "StabilityReserve: zero amount");

        blocToken.safeTransferFrom(msg.sender, address(this), amount);
        reserveBalance += amount;

        emit ReserveDeposited(amount, block.timestamp);
    }

    /**
     * @notice Check current price from Chainlink oracle
     * @return Current price (8 decimals)
     */
    function checkPrice() public view override returns (uint256) {
        if (address(priceFeed) == address(0)) {
            return 0;
        }

        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();

        require(answer > 0, "StabilityReserve: invalid price");
        require(updatedAt > block.timestamp - PRICE_STALENESS, "StabilityReserve: stale price");
        require(answeredInRound >= roundId, "StabilityReserve: stale round");

        return uint256(answer);
    }

    /**
     * @notice Execute buyback if price has dropped below threshold
     * @param amount Amount of reserve to use for buyback
     */
    function executeBuyback(uint256 amount) external override onlyOwner nonReentrant {
        require(amount > 0, "StabilityReserve: zero amount");
        require(amount <= reserveBalance, "StabilityReserve: insufficient reserve");
        require(address(router) != address(0), "StabilityReserve: router not set");
        require(address(priceFeed) != address(0), "StabilityReserve: price feed not set");

        uint256 currentPrice = checkPrice();

        // Check if price has dropped enough to trigger buyback
        uint256 dropThreshold = (lastPrice * (BASIS_POINTS - priceThreshold)) / BASIS_POINTS;
        require(currentPrice <= dropThreshold, "StabilityReserve: price above threshold");

        reserveBalance -= amount;

        // Sell reserve tokens for ETH, then buy back $BLOC
        // This is a simplified implementation - in production you'd want more sophisticated logic
        blocToken.safeTransfer(address(this), amount);

        // Update last price after buyback
        lastPrice = currentPrice;

        emit BuybackExecuted(amount, currentPrice, block.timestamp);
    }

    /**
     * @notice Get the current reserve balance
     * @return Reserve balance in tokens
     */
    function getReserveBalance() external view override returns (uint256) {
        return reserveBalance;
    }

    /**
     * @notice Update the price drop threshold for triggering buybacks
     * @param newThreshold New threshold in basis points
     */
    function updatePriceThreshold(uint256 newThreshold) external override onlyOwner {
        require(newThreshold > 0 && newThreshold <= MAX_THRESHOLD, "StabilityReserve: invalid threshold");

        uint256 oldThreshold = priceThreshold;
        priceThreshold = newThreshold;

        emit ThresholdUpdated(oldThreshold, newThreshold);
    }

    /**
     * @notice Update the last recorded price (for initialization or manual adjustment)
     */
    function updateLastPrice() external onlyOwner {
        require(address(priceFeed) != address(0), "StabilityReserve: price feed not set");
        lastPrice = checkPrice();
    }

    /**
     * @notice Emergency withdraw function
     * @param token Token to withdraw (use address(0) for ETH)
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            payable(owner()).transfer(amount);
        } else {
            IERC20(token).safeTransfer(owner(), amount);
            if (token == address(blocToken)) {
                reserveBalance -= amount;
            }
        }
    }

    receive() external payable {}
}
