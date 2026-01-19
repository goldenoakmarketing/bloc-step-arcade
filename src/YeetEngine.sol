// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IYeetEngine} from "./interfaces/IYeetEngine.sol";

/**
 * @title YeetEngine
 * @notice Commit-reveal randomness for yeet recipient selection
 * @dev Users commit a hash before quarter 5, then reveal on quarter 6 to generate random recipient
 */
contract YeetEngine is IYeetEngine, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable blocToken;

    mapping(address => bytes32) public commits;
    mapping(address => uint256) public commitBlock;
    mapping(address => uint256) public leaderboard;
    mapping(address => bool) private _isEligible;
    mapping(address => uint256) private eligibleUserIndex;

    address[] public eligibleUsers;
    address public arcadeVault;

    uint256 public constant COMMIT_EXPIRY_BLOCKS = 256;
    uint256 public constant MIN_COMMIT_DELAY = 1;

    modifier onlyVault() {
        require(msg.sender == arcadeVault, "YeetEngine: caller is not vault");
        _;
    }

    constructor(address _blocToken, address _owner) Ownable(_owner) {
        require(_blocToken != address(0), "YeetEngine: zero address");
        blocToken = IERC20(_blocToken);
    }

    /**
     * @notice Set the arcade vault address (can only be set once)
     * @param _arcadeVault The address of the ArcadeVault contract
     */
    function setArcadeVault(address _arcadeVault) external onlyOwner {
        require(arcadeVault == address(0), "YeetEngine: vault already set");
        require(_arcadeVault != address(0), "YeetEngine: zero address");
        arcadeVault = _arcadeVault;
    }

    /**
     * @notice Submit a commitment hash before triggering yeet
     * @param hash The keccak256 hash of (secret, sender)
     */
    function commit(bytes32 hash) external override {
        require(hash != bytes32(0), "YeetEngine: invalid hash");
        commits[msg.sender] = hash;
        commitBlock[msg.sender] = block.number;

        emit Committed(msg.sender, hash, block.number);
    }

    /**
     * @notice Reveal the secret to generate random recipient
     * @param secret The secret that was hashed in commit
     * @return recipient The randomly selected recipient
     */
    function reveal(bytes32 secret) external override returns (address recipient) {
        require(commits[msg.sender] != bytes32(0), "YeetEngine: no commit found");
        require(
            block.number > commitBlock[msg.sender] + MIN_COMMIT_DELAY,
            "YeetEngine: reveal too early"
        );
        require(
            block.number <= commitBlock[msg.sender] + COMMIT_EXPIRY_BLOCKS,
            "YeetEngine: commit expired"
        );

        bytes32 expectedHash = keccak256(abi.encodePacked(secret, msg.sender));
        require(commits[msg.sender] == expectedHash, "YeetEngine: invalid reveal");

        // Clear the commit
        delete commits[msg.sender];
        delete commitBlock[msg.sender];

        // Generate random seed using commit block hash and revealed secret
        bytes32 seed = keccak256(
            abi.encodePacked(
                blockhash(commitBlock[msg.sender] + MIN_COMMIT_DELAY),
                secret,
                msg.sender,
                block.timestamp
            )
        );

        recipient = _getRandomRecipient(seed);
        return recipient;
    }

    /**
     * @notice Add a user to the eligible yeet pool
     * @param user Address to add
     */
    function addEligibleUser(address user) external override onlyVault {
        require(user != address(0), "YeetEngine: zero address");
        require(!_isEligible[user], "YeetEngine: already eligible");

        _isEligible[user] = true;
        eligibleUserIndex[user] = eligibleUsers.length;
        eligibleUsers.push(user);

        emit EligibleUserAdded(user);
    }

    /**
     * @notice Remove a user from the eligible yeet pool
     * @param user Address to remove
     */
    function removeEligibleUser(address user) external override onlyVault {
        require(_isEligible[user], "YeetEngine: not eligible");

        _isEligible[user] = false;

        // Swap and pop for efficient removal
        uint256 index = eligibleUserIndex[user];
        uint256 lastIndex = eligibleUsers.length - 1;

        if (index != lastIndex) {
            address lastUser = eligibleUsers[lastIndex];
            eligibleUsers[index] = lastUser;
            eligibleUserIndex[lastUser] = index;
        }

        eligibleUsers.pop();
        delete eligibleUserIndex[user];

        emit EligibleUserRemoved(user);
    }

    /**
     * @notice Execute a yeet transfer (called by ArcadeVault)
     * @param from The sender of the yeet
     * @param to The recipient of the yeet
     * @param amount Amount to transfer
     */
    function executeYeet(
        address from,
        address to,
        uint256 amount
    ) external override onlyVault nonReentrant {
        require(from != address(0) && to != address(0), "YeetEngine: zero address");
        require(amount > 0, "YeetEngine: zero amount");

        // Update leaderboard
        leaderboard[from] += amount;

        // Transfer tokens from sender to recipient
        blocToken.safeTransferFrom(from, to, amount);

        emit YeetSent(from, to, amount, block.timestamp);
    }

    /**
     * @notice Get the top 20 yeeters
     * @return addresses Array of top yeeter addresses
     * @return amounts Array of corresponding yeeted amounts
     */
    function getLeaderboard()
        external
        view
        override
        returns (address[] memory addresses, uint256[] memory amounts)
    {
        uint256 length = eligibleUsers.length;
        uint256 resultLength = length > 20 ? 20 : length;

        addresses = new address[](resultLength);
        amounts = new uint256[](resultLength);

        // Create a copy for sorting
        address[] memory sortedUsers = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            sortedUsers[i] = eligibleUsers[i];
        }

        // Simple bubble sort for top 20 (acceptable for small arrays)
        for (uint256 i = 0; i < resultLength; i++) {
            uint256 maxIndex = i;
            for (uint256 j = i + 1; j < length; j++) {
                if (leaderboard[sortedUsers[j]] > leaderboard[sortedUsers[maxIndex]]) {
                    maxIndex = j;
                }
            }
            if (maxIndex != i) {
                (sortedUsers[i], sortedUsers[maxIndex]) = (sortedUsers[maxIndex], sortedUsers[i]);
            }
            addresses[i] = sortedUsers[i];
            amounts[i] = leaderboard[sortedUsers[i]];
        }

        return (addresses, amounts);
    }

    /**
     * @notice Get the count of eligible users
     * @return Number of eligible users
     */
    function getEligibleUsersCount() external view override returns (uint256) {
        return eligibleUsers.length;
    }

    /**
     * @notice Check if a user is eligible for yeets
     * @param user Address to check
     * @return True if eligible
     */
    function isEligible(address user) external view override returns (bool) {
        return _isEligible[user];
    }

    /**
     * @notice Get the total amount yeeted by a user
     * @param user Address to check
     * @return Total yeeted amount
     */
    function getYeetedAmount(address user) external view override returns (uint256) {
        return leaderboard[user];
    }

    /**
     * @notice Internal function to select random recipient from eligible users
     * @param seed Random seed for selection
     * @return Selected recipient address
     */
    function _getRandomRecipient(bytes32 seed) internal view returns (address) {
        require(eligibleUsers.length > 0, "YeetEngine: no eligible users");

        uint256 randomIndex = uint256(seed) % eligibleUsers.length;
        return eligibleUsers[randomIndex];
    }
}
