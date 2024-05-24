// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "../lib/forge-std/src/Script.sol";
//import {Script} from "forge-std/Script.sol";
import {Raffle} from "../src/Raffle.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {VRFv2CreateSubscription, VRFv2FundSubscription, VRFv2AddConsumer} from "./Interactions.s.sol";
import {console} from "../lib/forge-std/src/Test.sol";

contract DeployRaffle is Script {
    function run() external returns (Raffle, HelperConfig) {
        // obtain the applicable env config from HelperConfig contract
        // read default input params from .env file
        HelperConfig helperConfig = new HelperConfig(
            vm.envUint("RAFFLE_ENTRANCE_FEE"),
            vm.envUint("AUTOMATION_UPKEEP_INTERVAL"),
            uint32(vm.envUint("VRF_CALLBACK_GAS_LIMIT")));
        (
            uint256 raffleEntranceFee,
            uint256 automationUpkeepInterval,
            address vrfCoordinator,
            address vrfLinkToken,
            uint64 vrfSubscriptionId,
            bytes32 vrfGasLane,
            uint32 vrfCallbackGasLimit
        ) = helperConfig.s_activeNetworkConfig();

        // check if vrfSubscriptionId is valid, if not, create new subscription
        console.log("Create Subscription");
        VRFv2CreateSubscription vrfV2CreateSubscription = new VRFv2CreateSubscription(
            vrfCoordinator);
        vrfSubscriptionId = vrfV2CreateSubscription.run();

        // check if subscription has sufficient funds, if not, fund it
        console.log("Fund Subscription");
        VRFv2FundSubscription vfrv2FundSubscription = new VRFv2FundSubscription(
            address(vrfCoordinator), address(vrfLinkToken), vrfSubscriptionId);
        vfrv2FundSubscription.run();

        // deploy the Raffle contract using the env config obtained above
        console.log("Deploy Raffle");
        vm.startBroadcast();
        Raffle raffle = new Raffle(
            raffleEntranceFee,
            automationUpkeepInterval,
            vrfCoordinator,
            vrfGasLane,
            vrfSubscriptionId,
            vrfCallbackGasLimit);
        vm.stopBroadcast();

        // add Raffle contract as consumer to the VRF subscription
        console.log("Add Consume");
        VRFv2AddConsumer vrfV2AddConsumer = new VRFv2AddConsumer(
            address(vrfCoordinator), vrfSubscriptionId, address(raffle));
        vrfV2AddConsumer.run();

        // check if Automation upkeeps have been registered w/ sufficient funds

        return (raffle, helperConfig);
    }
}