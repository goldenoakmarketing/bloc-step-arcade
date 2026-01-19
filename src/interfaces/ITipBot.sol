// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ITipBot {
    // Events
    event TippingEnabled(address indexed user, uint256 timestamp);
    event TippingDisabled(address indexed user, uint256 timestamp);
    event TipExecuted(address indexed from, address indexed to, uint256 amount, uint256 timestamp);

    // Functions
    function enableTipping() external;
    function disableTipping() external;
    function executeTip(address from, address to, uint256 amount) external;
    function isEnabled(address user) external view returns (bool);
    function getRemainingDailyTips(address user) external view returns (uint256);
    function dailyTipLimit() external view returns (uint256);
    function minimumTip() external view returns (uint256);
}
