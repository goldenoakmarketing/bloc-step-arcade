// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IArcadeVault {
    // Events
    event TimePurchased(
        address indexed buyer,
        uint256 quarters,
        uint256 secondsAdded,
        uint256 newBalance,
        uint256 timestamp
    );
    event YeetTriggered(address indexed yeeter, uint8 quarterNumber, uint256 timestamp);
    event TimeConsumed(address indexed player, uint256 secondsUsed, uint256 remainingBalance, uint256 timestamp);
    event VaultDistributed(uint256 stakingAmt, uint256 stabilityAmt, uint256 profitAmt, uint256 timestamp);

    // Functions
    function buyQuarter() external;
    function buyDollar() external;
    function buyQuarters(uint256 count) external;
    function getTimeBalance(address user) external view returns (uint256);
    function consumeTime(address player, uint256 secondsToConsume) external;
    function distributeVault() external;
    function quarterAmount() external view returns (uint256);
    function quarterDuration() external view returns (uint256);
    function yeetTrigger() external view returns (uint256);
    function vaultBalance() external view returns (uint256);
    function getUserQuarterCount(address user) external view returns (uint8);
    function getTotalYeeted(address user) external view returns (uint256);
}
