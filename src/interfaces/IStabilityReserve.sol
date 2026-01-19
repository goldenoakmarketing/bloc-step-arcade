// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IStabilityReserve {
    // Events
    event ReserveDeposited(uint256 amount, uint256 timestamp);
    event BuybackExecuted(uint256 amount, uint256 price, uint256 timestamp);
    event ThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    // Functions
    function deposit(uint256 amount) external;
    function checkPrice() external view returns (uint256);
    function executeBuyback(uint256 amount) external;
    function getReserveBalance() external view returns (uint256);
    function updatePriceThreshold(uint256 newThreshold) external;
    function priceThreshold() external view returns (uint256);
    function lastPrice() external view returns (uint256);
}
