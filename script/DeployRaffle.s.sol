// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {Raffle} from "../src/Raffle.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
// deprecate VRF v2 interfaces in favor of VRF v2.5
//import {VRFCoordinatorV2Interface} from "../lib/foundry-chainlink-toolkit/src/interfaces/vrf/VRFCoordinatorV2Interface.sol";
import {IVRFCoordinatorV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import {VRFv2CreateSubscription, VRFv2TransferSubscription, 
        VRFv2FundSubscription, VRFv2AddConsumer} from "./Interactions.s.sol";
import {console} from "forge-std/Test.sol";

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
            uint256 vrfSubscriptionId,
            bytes32 vrfGasLane,
            uint32 vrfCallbackGasLimit
        ) = helperConfig.s_activeNetworkConfig();

        // if no existing vrfSubscriptionId, create new subscription
        console.log("Create Subscription");
        if (vrfSubscriptionId == 0) {
            console.log("No Existing Subscription. Create New Subscription");
            VRFv2CreateSubscription vrfV2CreateSubscription = new VRFv2CreateSubscription(
                vrfCoordinator);
            (vrfSubscriptionId,) = vrfV2CreateSubscription.run();

        }
        // if vrfSubscriptionId exists, test if valid by calling getSubscription()
        else {
            console.log("Before getSubscription()");
            (,,,address subOwner,) = IVRFCoordinatorV2Plus(vrfCoordinator).getSubscription(vrfSubscriptionId);
            console.log("Subscription Exists", subOwner, vrfSubscriptionId);
        }

        // check if subscription has sufficient funds, if not, fund it
        console.log("Fund Subscription");
        VRFv2FundSubscription vfrv2FundSubscription = new VRFv2FundSubscription(
            vrfCoordinator, vrfLinkToken, vrfSubscriptionId);
        vfrv2FundSubscription.run();

        // deploy the Raffle contract
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
        console.log("Add Consumer");
        VRFv2AddConsumer vrfV2AddConsumer = new VRFv2AddConsumer(
            vrfCoordinator, vrfSubscriptionId, address(raffle));
        vrfV2AddConsumer.run();

        // check if Automation upkeeps have been registered w/ sufficient funds

        return (raffle, helperConfig);
    }
}