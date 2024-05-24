// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "../lib/forge-std/src/Script.sol";
import {LinkTokenInterface} from "../lib/foundry-chainlink-toolkit/src/interfaces/shared/LinkTokenInterface.sol";
import {VRFCoordinatorV2Interface} from "../lib/foundry-chainlink-toolkit/src/interfaces/vrf/VRFCoordinatorV2Interface.sol";
import {VRFCoordinatorV2Mock} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {console} from "../lib/forge-std/src/Test.sol";

//////////////////////////////////////////////////////////////////////////////////
// Chainlink VRF /////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
// VRFv2CreateSubscription      creates a new Chainlink VRF subscription and    //
//                              returns its subId.                              //
// VRFv2FundSubscription        checks balance of subscription, tops it up if   //
//                              it's too low, and returns the final balance.    //
// VRFv2AddConsumer             adds a consumer to subscription and returns     //
//                              TRUE.                                           //
//////////////////////////////////////////////////////////////////////////////////

/**
 *  @notice This contract creates a new Chainlink VRF subscription using the 
 *          VRF coordinator passed in.
 */
contract VRFv2CreateSubscription is Script {
    address private i_vrfCoordinator;

    constructor(address vrfCoordinator) {
        i_vrfCoordinator = vrfCoordinator;
    }

    function run() external returns (uint64) {
        return createSubscription();
    }

    function createSubscription() internal returns (uint64 subId) {
        vm.startBroadcast();
        subId = VRFCoordinatorV2Interface(i_vrfCoordinator).createSubscription();
        vm.stopBroadcast();
        console.log("VRF Subscription created: ", subId);
        return subId;
    }
}


/**
 *  @notice This contract/script funds the Chainlink VRF subscription using 
 *          the VRF coordinator, Link Token, and subscription ID passed in.
 */
contract VRFv2FundSubscription is Script {
    address private immutable i_vrfCoordinator;
    address private immutable i_linkToken;
    uint64 private immutable i_subscriptionId;

    /* Functions */
    constructor(address vrfCoordinator, address linkToken, uint64 subId) {
        i_vrfCoordinator = vrfCoordinator;
        i_linkToken = linkToken;
        i_subscriptionId = subId;
    }

    function run() external returns (uint256) {
        return fundSubscription();
    }

    function fundSubscription() internal returns (uint256 balance) {
        // if subscription is not valid, getSubscription() reverts
        (balance,,,) = VRFCoordinatorV2Interface(i_vrfCoordinator).getSubscription(i_subscriptionId);
        uint256 minBalance = vm.envUint("VRF_MINIMUM_BALANCE");
        uint256 diff = minBalance - balance;
        if (diff > 0) {
            // perform the topup ///////////////////////////////////////////////////////////////////
            // on Anvil where Chainlink doesn't exist, the mock function fundSubscription() is used
            if (block.chainid == vm.envUint("DEFAULT_ANVIL_CHAINID")) {
                vm.startBroadcast();
                VRFCoordinatorV2Mock(i_vrfCoordinator).fundSubscription(i_subscriptionId, uint96(diff));
                vm.stopBroadcast();
            } 
            // on Sepolia Testnet or Eth Mainnet where Chainlink does exist, the actual funding 
            // function transferAndCall() is used
            else {
                // need to provide either the address or private key for an account that has sufficient 
                // funds to perform the transferAndCall() call
                //vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
                vm.startBroadcast(vm.envAddress("SEPOLIA_TESTNET_KEY_SENDER"));
                LinkTokenInterface(i_linkToken).transferAndCall(
                    i_vrfCoordinator,
                    diff,
                    abi.encode(i_subscriptionId)
                    );
                vm.stopBroadcast();
            }
            (balance,,,) = VRFCoordinatorV2Interface(i_vrfCoordinator).getSubscription(i_subscriptionId);
            console.log("Fund Subscription SUCCESS: ", balance);
            return balance;
        }
        console.log("Fund Subscription SKIPPED: ", balance);
        return balance;
    }
}


/**
 *  @notice This contract/script adds a consumer to the Chainlink VRF subscription 
 *          using the VRF coordinator, VRF consumer, and subscription ID passed in.
 */
contract VRFv2AddConsumer is Script {
    address private immutable i_vrfCoordinator;
    uint64 private immutable i_subscriptionId;
    address private immutable i_vrfConsumer;

    constructor(address vrfCoordinator, uint64 subId, address vrfConsumer) {
        i_vrfCoordinator = vrfCoordinator;
        i_subscriptionId = subId;
        i_vrfConsumer = vrfConsumer;
    }

    function run() external returns (bool) {
        return addConsumer();
    }

    function addConsumer() internal returns (bool) {
        vm.startBroadcast();
        VRFCoordinatorV2Interface(i_vrfCoordinator).addConsumer(i_subscriptionId, i_vrfConsumer);
        vm.stopBroadcast();
        console.log("Add Consumer SUCCESS: ", i_vrfConsumer);
        return true;
    }
}

//////////////////////////////////////////////////////////////////////////////////
// Chainlink Automation //////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
contract AutomationRegisterUpkeep is Script {
    function run() external {}
}

contract AutomationDeregisterUpkeep is Script {
    function run() external {}
}