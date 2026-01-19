// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ITipBot} from "./interfaces/ITipBot.sol";

/**
 * @title TipBot
 * @notice Authorize and execute Farcaster tips
 * @dev Users enable tipping for their wallet, then the authorized bot can execute tips on their behalf
 */
contract TipBot is ITipBot, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable blocToken;

    address public authorizedBot;
    uint256 public override dailyTipLimit;
    uint256 public override minimumTip;

    mapping(address => bool) public userTippingEnabled;
    mapping(address => mapping(uint256 => uint256)) public dailyTipCount;

    modifier onlyAuthorizedBot() {
        require(msg.sender == authorizedBot, "TipBot: caller is not authorized bot");
        _;
    }

    constructor(
        address _blocToken,
        address _authorizedBot,
        address _owner
    ) Ownable(_owner) {
        require(_blocToken != address(0), "TipBot: zero token address");
        require(_authorizedBot != address(0), "TipBot: zero bot address");

        blocToken = IERC20(_blocToken);
        authorizedBot = _authorizedBot;
        dailyTipLimit = 50;
        minimumTip = 100e18; // 100 $BLOC
    }

    /**
     * @notice Enable tipping for the caller's wallet
     */
    function enableTipping() external override {
        require(!userTippingEnabled[msg.sender], "TipBot: already enabled");

        userTippingEnabled[msg.sender] = true;

        emit TippingEnabled(msg.sender, block.timestamp);
    }

    /**
     * @notice Disable tipping for the caller's wallet
     */
    function disableTipping() external override {
        require(userTippingEnabled[msg.sender], "TipBot: not enabled");

        userTippingEnabled[msg.sender] = false;

        emit TippingDisabled(msg.sender, block.timestamp);
    }

    /**
     * @notice Execute a tip on behalf of an enabled user
     * @param from The user sending the tip
     * @param to The recipient of the tip
     * @param amount Amount of $BLOC to tip
     */
    function executeTip(
        address from,
        address to,
        uint256 amount
    ) external override onlyAuthorizedBot nonReentrant {
        require(from != address(0) && to != address(0), "TipBot: zero address");
        require(from != to, "TipBot: cannot tip yourself");
        require(userTippingEnabled[from], "TipBot: tipping not enabled");
        require(amount >= minimumTip, "TipBot: below minimum tip");

        uint256 today = block.timestamp / 1 days;
        require(
            dailyTipCount[from][today] < dailyTipLimit,
            "TipBot: daily limit reached"
        );

        dailyTipCount[from][today]++;

        blocToken.safeTransferFrom(from, to, amount);

        emit TipExecuted(from, to, amount, block.timestamp);
    }

    /**
     * @notice Check if a user has tipping enabled
     * @param user Address to check
     * @return True if tipping is enabled
     */
    function isEnabled(address user) external view override returns (bool) {
        return userTippingEnabled[user];
    }

    /**
     * @notice Get remaining daily tips for a user
     * @param user Address to check
     * @return Number of tips remaining today
     */
    function getRemainingDailyTips(address user) external view override returns (uint256) {
        uint256 today = block.timestamp / 1 days;
        uint256 used = dailyTipCount[user][today];

        if (used >= dailyTipLimit) {
            return 0;
        }

        return dailyTipLimit - used;
    }

    /**
     * @notice Update the authorized bot address
     * @param newBot New bot address
     */
    function setAuthorizedBot(address newBot) external onlyOwner {
        require(newBot != address(0), "TipBot: zero address");
        authorizedBot = newBot;
    }

    /**
     * @notice Update the daily tip limit
     * @param newLimit New daily limit
     */
    function setDailyTipLimit(uint256 newLimit) external onlyOwner {
        require(newLimit > 0, "TipBot: zero limit");
        dailyTipLimit = newLimit;
    }

    /**
     * @notice Update the minimum tip amount
     * @param newMinimum New minimum tip amount
     */
    function setMinimumTip(uint256 newMinimum) external onlyOwner {
        require(newMinimum > 0, "TipBot: zero minimum");
        minimumTip = newMinimum;
    }

    /**
     * @notice Get daily tip count for a user
     * @param user Address to check
     * @return Number of tips sent today
     */
    function getDailyTipCount(address user) external view returns (uint256) {
        uint256 today = block.timestamp / 1 days;
        return dailyTipCount[user][today];
    }
}
