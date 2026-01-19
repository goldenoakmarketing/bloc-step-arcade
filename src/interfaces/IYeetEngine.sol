// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IYeetEngine {
    // Events
    event Committed(address indexed user, bytes32 commitHash, uint256 blockNumber);
    event YeetSent(address indexed yeeter, address indexed recipient, uint256 amount, uint256 timestamp);
    event EligibleUserAdded(address indexed user);
    event EligibleUserRemoved(address indexed user);

    // Functions
    function commit(bytes32 hash) external;
    function reveal(bytes32 secret) external returns (address recipient);
    function addEligibleUser(address user) external;
    function removeEligibleUser(address user) external;
    function executeYeet(address from, address to, uint256 amount) external;
    function getLeaderboard() external view returns (address[] memory, uint256[] memory);
    function getEligibleUsersCount() external view returns (uint256);
    function isEligible(address user) external view returns (bool);
    function getYeetedAmount(address user) external view returns (uint256);
}
