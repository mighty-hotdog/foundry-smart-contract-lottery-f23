// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

//import {Script} from "forge-std/Script.sol";
//import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
//import {CreateVRFSubscription} from "./Interactions.s.sol";
import {Script, console} from "../lib/forge-std/src/Script.sol";
import {VRFCoordinatorV2Mock} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";

/**
 * @title   HelperConfig contract
 * @notice  This contract gathers up and returns the env config info for deployment of the Raffle contract.
 * @dev     Covers config for:
 *          1. Ethereum Testnet Sepolia
 *          2. Ethereum Mainnet
 *          3. Ethereum local network simulator Anvil
 *          Includes config info for Chainlink VRF and Chainlink Automation.
 *
 *          For Mainnet and Sepolia, contract reads chain-specific params from .env file.
 *          eg: chainid, vrfCoordinator address, linkToken address
 *
 *          For Anvil, contract deploys a mock vrfCoordinator contract and a mock linkToken contract
 *          and obtains the appropriate config info from them.
 */
contract HelperConfig is Script {
    /* Errors */
 
    /* Types */
    struct NetworkConfig {
        uint256 raffleEntranceFee;
        uint256 automationUpkeepInterval;
        address vrfCoordinator;
        address vrfLinkToken;
        uint64 vrfSubscriptionId;
        bytes32 vrfGasLane;
        uint32 vrfCallbackGasLimit;
    }

    /* State Variables */
    uint256 private immutable i_raffleEntranceFee;
    uint256 private immutable i_automationUpkeepInterval;
    uint32 private immutable i_vrfCallbackGasLimit;
    NetworkConfig public s_activeNetworkConfig;

    /* Functions */
    constructor(uint256 entranceFee, uint256 interval, uint32 callbackGasLimit) {
        uint256 fee;
        uint256 itv;
        uint32 glmt;
        console.log("Constructing HelperConfig contract...");
        if (entranceFee == 0) {
            fee = vm.envUint("RAFFLE_ENTRANCE_FEE");
            console.log("Default Raffle Entrance Fee set: ",fee);
        } else {
            fee = entranceFee;
        }
        if (interval == 0) {
            itv = vm.envUint("AUTOMATION_UPKEEP_INTERVAL");
            console.log("Default Automation Upkeep Interval set: ",itv);
        } else {
            itv = interval;
        }
        if (callbackGasLimit == 0) {
            glmt = uint32(vm.envUint("VRF_CALLBACK_GAS_LIMIT"));
            console.log("Default VRF Callback Gas Limit set: ",glmt);
        } else {
            glmt = callbackGasLimit;
        }
        i_raffleEntranceFee = fee;
        i_automationUpkeepInterval = itv;
        i_vrfCallbackGasLimit = glmt;

        if (block.chainid == vm.envUint("ETH_SEPOLIA_CHAINID")) {
            s_activeNetworkConfig = getSepoliaEthConfig();
        } else if (block.chainid == vm.envUint("ETH_MAINNET_CHAINID")) {
            s_activeNetworkConfig = getMainnetEthConfig();
        } else {
            s_activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() internal view returns (NetworkConfig memory) {
        console.log("Assembling NetworkConfig on Sepolia...");
        console.log("raffleEntranceFee: ",i_raffleEntranceFee);
        console.log("automationUpkeepInterval: ",i_automationUpkeepInterval);
        console.log("vrfCoordinator: ",vm.envAddress("ETH_SEPOLIA_VRFCOORDINATOR"));
        console.log("vrfLinkToken: ",vm.envAddress("ETH_SEPOLIA_LINK_TOKEN"));
        console.log("vrfSubscriptionId: ",vm.envOr("VRF_SUBSCRIPTION_ID_ETH_SEPOLIA",uint256(0)));
        console.log("vrfGasLane: ",vm.envString("ETH_SEPOLIA_GASLANE750"));     // need to read as string to console.log
        console.log("vrfCallbackGasLimit: ",i_vrfCallbackGasLimit);
        return NetworkConfig({
            raffleEntranceFee: i_raffleEntranceFee,
            automationUpkeepInterval: i_automationUpkeepInterval,
            vrfCoordinator: vm.envAddress("ETH_SEPOLIA_VRFCOORDINATOR"),
            vrfLinkToken: vm.envAddress("ETH_SEPOLIA_LINK_TOKEN"),
            vrfSubscriptionId: uint64(vm.envOr("VRF_SUBSCRIPTION_ID_ETH_SEPOLIA",uint256(0))),
            vrfGasLane: vm.envBytes32("ETH_SEPOLIA_GASLANE750"),
            vrfCallbackGasLimit: i_vrfCallbackGasLimit
        });
    }

    function getMainnetEthConfig() internal view returns (NetworkConfig memory) {
        console.log("Assembling NetworkConfig on Mainnet...");
        console.log("raffleEntranceFee: ",i_raffleEntranceFee);
        console.log("automationUpkeepInterval: ",i_automationUpkeepInterval);
        console.log("vrfCoordinator: ",vm.envAddress("ETH_MAINNET_VRFCOORDINATOR"));
        console.log("vrfLinkToken: ",vm.envAddress("ETH_MAINNET_LINK_TOKEN"));
        console.log("vrfSubscriptionId: ",vm.envOr("VRF_SUBSCRIPTION_ID_ETH_MAINNET",uint256(0)));
        console.log("vrfGasLane: ",vm.envString("ETH_MAINNET_GASLANE200"));     // need to read as string to console.log
        console.log("vrfCallbackGasLimit: ",i_vrfCallbackGasLimit);
        return NetworkConfig({
            raffleEntranceFee: i_raffleEntranceFee,
            automationUpkeepInterval: i_automationUpkeepInterval,
            vrfCoordinator: vm.envAddress("ETH_MAINNET_VRFCOORDINATOR"),
            vrfLinkToken: vm.envAddress("ETH_MAINNET_LINK_TOKEN"),
            vrfSubscriptionId: uint64(vm.envOr("VRF_SUBSCRIPTION_ID_ETH_MAINNET",uint256(0))),
            vrfGasLane: vm.envBytes32("ETH_MAINNET_GASLANE200"),
            vrfCallbackGasLimit: i_vrfCallbackGasLimit
        });
    }

    function getOrCreateAnvilEthConfig() internal returns (NetworkConfig memory) {
        // if there is an existing Anvil config, return that right away.
        if (s_activeNetworkConfig.vrfCoordinator != address(0)) {
            console.log("Returning existing NetworkConfig on Anvil...");
            console.log("raffleEntranceFee: ",s_activeNetworkConfig.raffleEntranceFee);
            console.log("automationUpkeepInterval: ",s_activeNetworkConfig.automationUpkeepInterval);
            console.log("vrfCoordinator: ",s_activeNetworkConfig.vrfCoordinator);
            console.log("vrfLinkToken: ",s_activeNetworkConfig.vrfLinkToken);
            console.log("vrfSubscriptionId: ",s_activeNetworkConfig.vrfSubscriptionId);
            // need to log as 2 lines
            console.log("vrfGasLane: ");
            console.logBytes32(s_activeNetworkConfig.vrfGasLane);

            console.log("vrfCallbackGasLimit: ",s_activeNetworkConfig.vrfCallbackGasLimit);
            return s_activeNetworkConfig;
        }

        // if there is no existing Anvil config, deploy a mock VRFCoordinator and LinkToken, 
        // and use them to generate new Anvil config
        uint96 baseFee = uint96(vm.envUint("BASE_FEE"));
        uint96 gasPriceLink = uint96(vm.envUint("GAS_PRICE_LINK"));
        vm.startBroadcast();
        VRFCoordinatorV2Mock vrfCoordinatorV2Mock = new VRFCoordinatorV2Mock(baseFee,gasPriceLink);
        LinkToken linkToken = new LinkToken();
        vm.stopBroadcast();
        console.log("No existing NetworkConfig on Anvil...");
        console.log("Deployed Mock VRF Coordinator on Anvil: ",address(vrfCoordinatorV2Mock));
        console.log("Deployed Mock Link Token on Anvil: ",address(linkToken));

        console.log("Assembling NetworkConfig on Anvil...");
        console.log("raffleEntranceFee: ",i_raffleEntranceFee);
        console.log("automationUpkeepInterval: ",i_automationUpkeepInterval);
        console.log("vrfCoordinator: ",address(vrfCoordinatorV2Mock));
        console.log("vrfLinkToken: ",address(linkToken));
        console.log("vrfSubscriptionId: ",uint64(0));
        console.log("vrfGasLane (not used): 0x1234");
        console.log("vrfCallbackGasLimit: ",i_vrfCallbackGasLimit);
        return NetworkConfig({
            raffleEntranceFee: i_raffleEntranceFee,
            automationUpkeepInterval: i_automationUpkeepInterval,
            vrfCoordinator: address(vrfCoordinatorV2Mock),
            vrfLinkToken: address(linkToken),
            vrfSubscriptionId: uint64(0),
            vrfGasLane: bytes32("0x1234"),    // doesn't matter what is put here
            vrfCallbackGasLimit: i_vrfCallbackGasLimit
        });
    }
}