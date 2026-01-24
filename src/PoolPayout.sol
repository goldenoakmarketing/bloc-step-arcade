// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract PoolPayout is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable blocToken;
    address public gameServer;
    uint256 public totalClaimed;

    event Claimed(address indexed player, uint256 amount, uint256 timestamp);
    event GameServerUpdated(address indexed oldServer, address indexed newServer);

    error NotAuthorized();
    error ZeroAddress();
    error InsufficientBalance();

    constructor(address _blocToken, address _owner) Ownable(_owner) {
        if (_blocToken == address(0)) revert ZeroAddress();
        blocToken = IERC20(_blocToken);
    }

    function setGameServer(address _gameServer) external onlyOwner {
        if (_gameServer == address(0)) revert ZeroAddress();
        address oldServer = gameServer;
        gameServer = _gameServer;
        emit GameServerUpdated(oldServer, _gameServer);
    }

    function claim(address player, uint256 amount) external {
        if (msg.sender != gameServer) revert NotAuthorized();
        if (player == address(0)) revert ZeroAddress();
        if (blocToken.balanceOf(address(this)) < amount) revert InsufficientBalance();

        totalClaimed += amount;
        blocToken.safeTransfer(player, amount);
        emit Claimed(player, amount, block.timestamp);
    }

    function getBalance() external view returns (uint256) {
        return blocToken.balanceOf(address(this));
    }

    function getQuarterBalance() external view returns (uint256) {
        return blocToken.balanceOf(address(this)) / 250e18;
    }

    function emergencyWithdraw(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        blocToken.safeTransfer(to, amount);
    }
}
