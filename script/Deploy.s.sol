// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ArcadeVault} from "../src/ArcadeVault.sol";
import {YeetEngine} from "../src/YeetEngine.sol";
import {StakingPool} from "../src/StakingPool.sol";
import {StabilityReserve} from "../src/StabilityReserve.sol";
import {TipBot} from "../src/TipBot.sol";

/**
 * @title Deploy
 * @notice Deployment script for Bloc Step Arcade contracts
 * @dev Run with: forge script script/Deploy.s.sol:Deploy --rpc-url <RPC_URL> --broadcast
 */
contract Deploy is Script {
    // Configuration - update these before deployment
    address public blocToken; // $BLOC token address (Mint Club)
    address public priceFeed; // Chainlink price feed for $BLOC
    address public router; // DEX router for buybacks
    address public owner; // Contract owner/admin
    address public profitWallet; // Wallet to receive profit share
    address public gameServer; // Game server address for time consumption
    address public tipBot; // Authorized bot for tipping

    // Deployed contract addresses
    ArcadeVault public arcadeVault;
    YeetEngine public yeetEngine;
    StakingPool public stakingPool;
    StabilityReserve public stabilityReserve;
    TipBot public tipBotContract;

    function setUp() public {
        // Load configuration from environment variables
        blocToken = vm.envAddress("BLOC_TOKEN_ADDRESS");
        owner = vm.envAddress("OWNER_ADDRESS");
        profitWallet = vm.envAddress("PROFIT_WALLET_ADDRESS");
        gameServer = vm.envAddress("GAME_SERVER_ADDRESS");
        tipBot = vm.envAddress("TIP_BOT_ADDRESS");

        // Optional: Chainlink price feed (can be zero for initial deployment)
        priceFeed = vm.envOr("PRICE_FEED_ADDRESS", address(0));

        // Optional: DEX router (can be zero for initial deployment)
        router = vm.envOr("ROUTER_ADDRESS", address(0));
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy StakingPool
        console.log("Deploying StakingPool...");
        stakingPool = new StakingPool(blocToken, owner);
        console.log("StakingPool deployed at:", address(stakingPool));

        // 2. Deploy YeetEngine
        console.log("Deploying YeetEngine...");
        yeetEngine = new YeetEngine(blocToken, owner);
        console.log("YeetEngine deployed at:", address(yeetEngine));

        // 3. Deploy StabilityReserve
        console.log("Deploying StabilityReserve...");
        stabilityReserve = new StabilityReserve(blocToken, priceFeed, router, owner);
        console.log("StabilityReserve deployed at:", address(stabilityReserve));

        // 4. Deploy TipBot
        console.log("Deploying TipBot...");
        tipBotContract = new TipBot(blocToken, tipBot, owner);
        console.log("TipBot deployed at:", address(tipBotContract));

        // 5. Deploy ArcadeVault (core contract)
        console.log("Deploying ArcadeVault...");
        arcadeVault = new ArcadeVault(blocToken, owner, profitWallet);
        console.log("ArcadeVault deployed at:", address(arcadeVault));

        // 6. Configure contract relationships
        console.log("Configuring contract relationships...");

        // Set ArcadeVault references
        arcadeVault.setStakingPool(address(stakingPool));
        arcadeVault.setStabilityReserve(address(stabilityReserve));
        arcadeVault.setYeetEngine(address(yeetEngine));
        arcadeVault.setGameServer(gameServer);

        // Set vault references in other contracts
        stakingPool.setArcadeVault(address(arcadeVault));
        stabilityReserve.setArcadeVault(address(arcadeVault));
        yeetEngine.setArcadeVault(address(arcadeVault));

        vm.stopBroadcast();

        // Log deployment summary
        console.log("\n========== DEPLOYMENT SUMMARY ==========");
        console.log("Network: Base");
        console.log("Owner:", owner);
        console.log("BLOC Token:", blocToken);
        console.log("");
        console.log("Contracts:");
        console.log("  ArcadeVault:", address(arcadeVault));
        console.log("  YeetEngine:", address(yeetEngine));
        console.log("  StakingPool:", address(stakingPool));
        console.log("  StabilityReserve:", address(stabilityReserve));
        console.log("  TipBot:", address(tipBotContract));
        console.log("=========================================\n");
    }
}

/**
 * @title DeployTestnet
 * @notice Deployment script for testnet with mock token
 */
contract DeployTestnet is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy mock token for testing
        // In production, use the actual $BLOC token from Mint Club
        MockBLOC mockToken = new MockBLOC();
        console.log("Mock BLOC deployed at:", address(mockToken));

        // Deploy all contracts
        StakingPool stakingPool = new StakingPool(address(mockToken), deployer);
        YeetEngine yeetEngine = new YeetEngine(address(mockToken), deployer);
        StabilityReserve stabilityReserve = new StabilityReserve(
            address(mockToken),
            address(0), // No price feed on testnet
            address(0), // No router on testnet
            deployer
        );
        TipBot tipBot = new TipBot(address(mockToken), deployer, deployer);
        ArcadeVault arcadeVault = new ArcadeVault(address(mockToken), deployer, deployer);

        // Configure relationships
        arcadeVault.setStakingPool(address(stakingPool));
        arcadeVault.setStabilityReserve(address(stabilityReserve));
        arcadeVault.setYeetEngine(address(yeetEngine));
        arcadeVault.setGameServer(deployer);

        stakingPool.setArcadeVault(address(arcadeVault));
        stabilityReserve.setArcadeVault(address(arcadeVault));
        yeetEngine.setArcadeVault(address(arcadeVault));

        // Mint some tokens to deployer for testing
        mockToken.mint(deployer, 1_000_000e18);

        vm.stopBroadcast();

        console.log("\n========== TESTNET DEPLOYMENT ==========");
        console.log("Mock BLOC:", address(mockToken));
        console.log("ArcadeVault:", address(arcadeVault));
        console.log("YeetEngine:", address(yeetEngine));
        console.log("StakingPool:", address(stakingPool));
        console.log("StabilityReserve:", address(stabilityReserve));
        console.log("TipBot:", address(tipBot));
        console.log("=========================================\n");
    }
}

/**
 * @title MockBLOC
 * @notice Simple mock token for testnet deployment
 */
contract MockBLOC {
    string public name = "Mock BLOC";
    string public symbol = "mBLOC";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        return _transfer(from, to, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}
