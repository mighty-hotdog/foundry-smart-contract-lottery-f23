// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "../lib/forge-std/src/Script.sol";
//import {LinkTokenInterface} from "../lib/foundry-chainlink-toolkit/src/interfaces/shared/LinkTokenInterface.sol";
import {LinkTokenInterface} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
//import {VRFCoordinatorV2Interface} from "../lib/foundry-chainlink-toolkit/src/interfaces/vrf/VRFCoordinatorV2Interface.sol";
//import {VRFCoordinatorV2Mock} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {IVRFCoordinatorV2Plus} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import {VRFCoordinatorV2_5Mock} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {console} from "../lib/forge-std/src/Test.sol";

//////////////////////////////////////////////////////////////////////////////////
// Chainlink VRF /////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
// VRFv2CreateSubscription      creates a new Chainlink VRF subscription and    //
//                              returns its subId.                              //
// VRFv2TransferSubscription    transfers an existing Chainlink VRF subscription//
//                              from its existing owner to a new owner.         //
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
    address private immutable i_vrfCoordinator;

    constructor(address vrfCoordinator) {
        i_vrfCoordinator = vrfCoordinator;
    }

    function run() external returns (uint256, address) {
        return createSubscription();
    }

    function createSubscription() internal returns (uint256 subId, address subOwner) {
        vm.startBroadcast();
        subId = IVRFCoordinatorV2Plus(i_vrfCoordinator).createSubscription();
        vm.stopBroadcast();
        (,,,subOwner,) = IVRFCoordinatorV2Plus(i_vrfCoordinator).getSubscription(subId);
        console.log("VRF Subscription created: ", i_vrfCoordinator, subOwner, subId);
        return (subId, subOwner);
    }
}


/**
 *  @notice This contract transfers an existing Chainlink VRF subscription
 *          from its existing owner to a new owner.
 *  @dev    The initiating function requestSubscriptionOwnerTransfer() can
 *          only be called by the existing subscription owner.
 *          The receiving function acceptSubscriptionOwnerTransfer() must
 *          be called by the new subscription owner.
 */
contract VRFv2TransferSubscription is Script {
    address private immutable i_vrfCoordinator;
    address private immutable i_vrfSubOwner;
    address private immutable i_vrfNewSubOwner;
    uint256 private immutable i_subscriptionId;

    constructor(address vrfCoordinator, address subOwner, address newOwner, uint256 subId) {
        i_vrfCoordinator = vrfCoordinator;
        i_vrfSubOwner = subOwner;
        i_vrfNewSubOwner = newOwner;
        i_subscriptionId = subId;
    }

    function run() external returns (uint256 subId, address owner, address newOwner) {
        return transferSubscription();
    }

    function transferSubscription() internal returns (uint256 subId, address owner, address newOwner) {
        // calling requestSubscriptionOwnerTransfer() as existing subscription owner
        vm.startBroadcast(i_vrfSubOwner);
        IVRFCoordinatorV2Plus(i_vrfCoordinator).requestSubscriptionOwnerTransfer(
            i_subscriptionId,
            i_vrfNewSubOwner);
        vm.stopBroadcast();

        // calling acceptSubscriptionOwnerTransfer() as the new subscription owner
        vm.startBroadcast(i_vrfNewSubOwner);
        IVRFCoordinatorV2Plus(i_vrfCoordinator).acceptSubscriptionOwnerTransfer(
            i_subscriptionId);
        vm.stopBroadcast();
        console.log("VRF Subscription transferred: ",
            i_vrfSubOwner, 
            i_vrfNewSubOwner,
            i_subscriptionId);
        return (i_subscriptionId, i_vrfSubOwner, i_vrfNewSubOwner);
    }
}


/**
 *  @notice This contract/script funds the Chainlink VRF subscription if it
 *          is below the minimum balance.
 *  @dev    On Anvil, the mock fundSubscription() is called. But on Testnet or Mainnet,
 *          the actual transferAndCall() provided by Chainlink is called instead.
 */
contract VRFv2FundSubscription is Script {
    address private immutable i_vrfCoordinator;
    address private immutable i_linkToken;
    uint256 private immutable i_subscriptionId;

    /* Functions */
    constructor(address vrfCoordinator, address linkToken, uint256 subId) {
        i_vrfCoordinator = vrfCoordinator;
        i_linkToken = linkToken;
        i_subscriptionId = subId;
    }

    function run() external returns (uint256) {
        return fundSubscription();
    }

    function fundSubscription() internal returns (uint256 balance) {
        // if subscription is not valid, getSubscription() reverts
        (balance,,,,) = IVRFCoordinatorV2Plus(i_vrfCoordinator).getSubscription(i_subscriptionId);
        uint256 minBalance = vm.envUint("VRF_MINIMUM_BALANCE");
        uint256 diff = minBalance - balance;
        if (diff > 0) {
            // perform the topup ///////////////////////////////////////////////////////////////////
            // on Anvil where Chainlink doesn't exist, the mock function fundSubscription() is used
            if (block.chainid == vm.envUint("DEFAULT_ANVIL_CHAINID")) {
                vm.startBroadcast();
                VRFCoordinatorV2_5Mock(i_vrfCoordinator).fundSubscription(i_subscriptionId, uint96(diff));
                vm.stopBroadcast();
            } 
            // on Sepolia Testnet or Eth Mainnet where Chainlink does exist, the actual funding 
            // function transferAndCall() is used
            else {
                // calling transferAndCall() as a wallet/account that has sufficient funds to do the funding
                // this wallet/account can be provided as an address or private key
                //vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
                vm.startBroadcast(vm.envAddress("SEPOLIA_TESTNET_KEY_SENDER"));
                LinkTokenInterface(i_linkToken).transferAndCall(
                    i_vrfCoordinator,
                    diff,
                    abi.encode(i_subscriptionId)
                    );
                vm.stopBroadcast();
            }
            (balance,,,,) = IVRFCoordinatorV2Plus(i_vrfCoordinator).getSubscription(i_subscriptionId);
            console.log("Fund Subscription SUCCESS: ", i_vrfCoordinator, i_subscriptionId, balance);
            return balance;
        }
        console.log("Fund Subscription SKIPPED: ", i_vrfCoordinator, i_subscriptionId, balance);
        return balance;
    }
}


/**
 *  @notice This contract/script adds a consumer to the Chainlink VRF subscription.
 *  @dev    addConsumer() can only be called by the subscription owner.
 */
contract VRFv2AddConsumer is Script {
    address private immutable i_vrfCoordinator;
    uint256 private immutable i_subscriptionId;
    address private immutable i_vrfConsumer;

    constructor(address vrfCoordinator, uint256 subId, address vrfConsumer) {
        i_vrfCoordinator = vrfCoordinator;
        i_subscriptionId = subId;
        i_vrfConsumer = vrfConsumer;
    }

    function run() external returns (bool) {
        return addConsumer();
    }

    function addConsumer() internal returns (bool) {
        // calling addConsumer() as subscription owner
        (,,,address owner,) = IVRFCoordinatorV2Plus(i_vrfCoordinator).getSubscription(i_subscriptionId);
        vm.startBroadcast(owner);
        IVRFCoordinatorV2Plus(i_vrfCoordinator).addConsumer(i_subscriptionId, i_vrfConsumer);
        vm.stopBroadcast();
        console.log("Add Consumer SUCCESS: ", i_vrfCoordinator, i_subscriptionId, i_vrfConsumer);
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