// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

// deprecate VRF v2 interfaces in favor of VRF v2.5
//import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
//import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {IVRFCoordinatorV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {console} from "forge-std/Test.sol";

/**
 * @title   A sample Raffle contract
 * @notice  This contract creates a sample raffle.
 * @dev     Implements Chainlink VRFv2 and Chainlink Automation.
 */
//contract Raffle is VRFConsumerBaseV2 {
contract Raffle is VRFConsumerBaseV2Plus {
    /* Errors **********************************************************/
    error Raffle__NotOwner(address caller);
    error Raffle__InvalidEntranceFeeSet();
    error Raffle__InvalidIntervalSet();
    error Raffle__InvalidVrfCoordinatorAddressSet();
    error Raffle__InvalidVrfGasLaneSet();
    error Raffle__InvalidVrfSubscriptionIdSet();
    error Raffle__InvalidVrfCallbackGasLimitSet();
    error Raffle__RaffleNotOpen();
    error Raffle__RaffleIsFull();
    error Raffle__NotEnoughEthSent();
    error Raffle__InvalidPlayerAddress();
    error Raffle__FailedPayoutToWinner();
    error Raffle__OwnerNotAllowedAsPlayer();
    error Raffle__PlayerAlreadyExists(address player);
    error Raffle__UpkeepNotNeeded(
        RaffleState raffleState,
        uint256 contractBalance,
        uint256 numberOfPlayers
    );
    error Raffle__InvalidWinnerAddress();

    /* Types ***********************************************************/
    enum RaffleState {
        OPEN,
        PROCESSING,
        CLOSED
    }

    /* State Variables *************************************************/
    uint16 public constant VRF_REQUEST_CONFIRMATION_BLOCKS = 3;
    uint32 public constant VRF_NUMWORDS_REQUESTED = 1;
    uint256 public constant MAX_NUM_OF_PLAYERS = 50;
    address private immutable i_raffleContractOwner;
    uint256 private immutable i_raffleEntranceFee;
    uint256 private immutable i_vrfUpkeepInterval;
    address private immutable i_vrfCoordinator;
    bytes32 private immutable i_vrfGasLane;
    uint256 private immutable i_vrfSubscriptionId;
    uint32 private immutable i_vrfCallbackGasLimit;
    address payable[] private s_rafflePlayers;
    RaffleState private s_raffleState;
    uint256 private s_raffleOpenTimeStamp;
    uint256 private s_vrfRequestId;
    address private s_lastWinner;

    /* Events **********************************************************/
    event raffleIsOpen(uint256 indexed timeStamp);
    event raffleIsProcessing(uint256 indexed timeStamp);
    event raffleIsClosed(uint256 indexed timeStamp);
    event maxNumOfPlayersEntered(uint256 indexed maxNumberOfPlayers, uint256 indexed timestamp);
    event forcedCleanupInitiated(uint256 indexed timestamp);
    event forcedResetInitiated(uint256 indexed timestamp);
    event playerEnteredRaffle(
        address indexed playerAddress,
        uint256 indexed amountPaid,
        uint256 indexed timeStamp
    );
    event vrfRequestMade(
        uint256 indexed vrfRequestId, 
        uint256 indexed timestamp
    );
    event winnerSelected(
        address indexed winnerAddress,
        uint256 indexed timeStamp
    );
    event payoutToWinnerCompleted(
        address indexed winnerAddress,
        uint256 indexed amountWon,
        uint256 indexed timeStamp
    );

    /* Functions *******************************************************/
    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
//    ) VRFConsumerBaseV2(vrfCoordinator) {
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        // Perform all revert checks 1st before doing anything that might cost gas.
        if (entranceFee == 0) {
            revert Raffle__InvalidEntranceFeeSet();
        }
        if (interval == 0) {
            revert Raffle__InvalidIntervalSet();
        }
        if (vrfCoordinator == address(0)) {
            revert Raffle__InvalidVrfCoordinatorAddressSet();
        }
        if (gasLane == bytes32(0)) {
            revert Raffle__InvalidVrfGasLaneSet();
        }
        if (subscriptionId == 0) {
            revert Raffle__InvalidVrfSubscriptionIdSet();
        }
        if (callbackGasLimit == 0) {
            revert Raffle__InvalidVrfCallbackGasLimitSet();
        }

        // After all revert checks passed, then proceed to stuff that cost gas.
        i_raffleContractOwner = msg.sender;
        i_raffleEntranceFee = entranceFee;
        i_vrfUpkeepInterval = interval;
        i_vrfCoordinator = vrfCoordinator;
        i_vrfGasLane = gasLane;
        i_vrfSubscriptionId = subscriptionId;
        i_vrfCallbackGasLimit = callbackGasLimit;
        s_raffleState = RaffleState.OPEN;
        // Accessing block.timestamp is cheaper than accessing raffleOpenTimeStamp.
        //  Unfortunately, block.timestamp will be different if called again for the emit,
        //  hence there is no choice but to use a memory variable raffleOpenTimeStamp to
        //  pass the data around.
        uint256 raffleOpenTimeStamp = block.timestamp;
        s_raffleOpenTimeStamp = raffleOpenTimeStamp;
        emit raffleIsOpen(raffleOpenTimeStamp);
    }

    /**
     * @notice  Function. Allows external to pay for a ticket and join the raffle.
     */
    function enterRaffle() public payable {
        if (s_rafflePlayers.length == MAX_NUM_OF_PLAYERS) {
            revert Raffle__RaffleIsFull();
        }
        if (msg.value < i_raffleEntranceFee) {
            revert Raffle__NotEnoughEthSent();
        }
        if (msg.sender == i_raffleContractOwner) {
            revert Raffle__OwnerNotAllowedAsPlayer();
        }
        if (playerExists(msg.sender)) {
            revert Raffle__PlayerAlreadyExists(msg.sender);
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        s_rafflePlayers.push(payable(msg.sender));
        emit playerEnteredRaffle(msg.sender, msg.value, block.timestamp);
        if (s_rafflePlayers.length == MAX_NUM_OF_PLAYERS) {
            emit maxNumOfPlayersEntered(MAX_NUM_OF_PLAYERS, block.timestamp);
        }
    }

    function playerExists(address player) internal view returns (bool) {
        for(uint i=0; i<s_rafflePlayers.length; i++) {
            if (s_rafflePlayers[i] == player) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice  Function. Defines logic for Chainlink Automation (customlogic upkeep) 
     *          to determine if it is time to perform upkeep.
     * @dev     This function returns true when all of the following are true:
     *          1. time interval has passed between raffle runs
     *          2. raffle is OPEN
     *          3. contract has players and eth
     *          Chainlink doesn't actually call this function but simulates the logic offchain.
     *          When logic returns true, Chainlink calls performUpkeep().
     */
    function checkUpkeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool isTime = (block.timestamp - s_raffleOpenTimeStamp) >= i_vrfUpkeepInterval;
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasEth = address(this).balance > 0;
        bool hasPlayers = s_rafflePlayers.length > 1;
        upkeepNeeded = isTime && isOpen && hasEth && hasPlayers;
        return (upkeepNeeded, "");
    }

    /**
     * @notice  Function. Chainlink Automation calls when checkUpkeep() logic returns 
     *          true. Kicks off process of picking a winner.
     * @dev     Sets raffle to close and makes request to Chainlink VRF for random number.
     */
    function performUpkeep(bytes calldata /* performData */) external {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                s_raffleState,
                address(this).balance,
                s_rafflePlayers.length
            );
        }
        s_raffleState = RaffleState.PROCESSING;
        emit raffleIsProcessing(block.timestamp);

        // request random number from Chainlink VRF
        /* old VRFV2 interfaces
        s_vrfRequestId = VRFCoordinatorV2Interface(i_vrfCoordinator).requestRandomWords(
            i_vrfGasLane, // gas lane
            i_vrfSubscriptionId, // subscription acct in Chainlink
            VRF_REQUEST_CONFIRMATION_BLOCKS, // # of blocks for confirmation
            i_vrfCallbackGasLimit, // limits gas for getting back random number
            VRF_NUMWORDS_REQUESTED // # of random numbers to ask for
        );
        */
        // new VRFV2.5 interfaces
        s_vrfRequestId = IVRFCoordinatorV2Plus(i_vrfCoordinator).requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: i_vrfGasLane,
                subId: i_vrfSubscriptionId,
                requestConfirmations: VRF_REQUEST_CONFIRMATION_BLOCKS,
                callbackGasLimit: i_vrfCallbackGasLimit,
                numWords: VRF_NUMWORDS_REQUESTED,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            })
        );
        emit vrfRequestMade(s_vrfRequestId, block.timestamp);
    }

    /**
     * @notice  Function. Internal. Overide. Picks winner and pays out entire pot to winner.
     * @dev     Triggered by Chainlink VRF in reply to earlier requestRandomWords() call 
     *          in performUpkeep().
     *          1. receives a random number from Chainlink VRF
     *          2. picks a winner using this random number
     *          3. checks that winner address is valid, then pays entire contract balance to winner
     *          4. reset raffle
     */
    function fulfillRandomWords(
        uint256 /* _requestId */,
        //uint256[] memory _randomWords     // old VRFV2 interface
        uint256[] calldata _randomWords     // new VRFV2.5 interface
    ) internal override {
        // pick winner from list of all players using received random number
        uint256 indexOfWinner = _randomWords[0] % s_rafflePlayers.length;
        address payable winner = s_rafflePlayers[indexOfWinner];

        // check that winner address is valid
        if (winner == address(0)) {
            revert Raffle__InvalidWinnerAddress();
        }
        emit winnerSelected(winner, block.timestamp);
        s_lastWinner = winner;

        // payout entire contract balance to winner
        uint256 amountWon = address(this).balance;
        (bool success, ) = winner.call{value: amountWon}("");
        if (!success) {
            revert Raffle__FailedPayoutToWinner();
        }
        emit payoutToWinnerCompleted(winner, amountWon, block.timestamp);

        resetRaffle();
        console.log("End of fulfillRandomWords()");
        console.log("msg.sender balance: ",msg.sender.balance);
        console.log("Raffle balance: ",address(this).balance);
    }

    /**
     * @notice  Function. Internal. Resets raffle for next round.
     */
    function resetRaffle() internal {
        cleanupRaffle();
        s_raffleState = RaffleState.OPEN;
        uint256 raffleOpenTimeStamp = block.timestamp;
        s_raffleOpenTimeStamp = raffleOpenTimeStamp;
        emit raffleIsOpen(raffleOpenTimeStamp);
    }

    /**
     * @notice  Function. Internal. Performs cleanup of contract. Part of resetting the raffle.
     */
    function cleanupRaffle() internal {
        s_rafflePlayers = new address payable[](0);
        // probably also need to cleanup:
        // 1. hanging VRF requests that are no longer wanted/valid
        // 2. hanging Automation triggers that are no longer wanted/valid
        // maybe return a bool to indicate cleanup success or failure?
    }

    function cleanupRaffleForced() external onlyOwnerMayCall {
        emit forcedCleanupInitiated(block.timestamp);
        cleanupRaffle();
    }

    function resetRaffleForced() external onlyOwnerMayCall {
        emit forcedResetInitiated(block.timestamp);
        resetRaffle();
    }

    /**
     * @notice  Mechanism to automatically trigger raffle to start picking winners. After certain conditions have been met.
     * @dev     Uses some kind of events. Time-triggered and condition-triggered.
     */

    /**
     * @notice  fallback() and receive() functions
     * @dev     If eth is sent to the contract without enterRaffle() being called, eg: directly from a wallet, 
     *          or from another contract that didn't call enterRaffle().
     *          Let enterRaffle() handle it anyway.
     */
    fallback() external payable {
        enterRaffle();
    }
    receive() external payable {
        enterRaffle();
    }

    /* Getter Functions ************************************************/
    function getRaffleOwner() external view returns (address) {
        return i_raffleContractOwner;
    }

    function getEntranceFee() external view returns (uint256) {
        return i_raffleEntranceFee;
    }

    function getAutomationUpkeepInterval() external view returns (uint256) {
        return i_vrfUpkeepInterval;
    }

    function getVrfCoordinator() external view returns (address) {
        return i_vrfCoordinator;
    }

    function getGasLane() external view returns (bytes32) {
        return i_vrfGasLane;
    }

    function getVrfSubscriptionId() external view returns (uint256) {
        return i_vrfSubscriptionId;
    }

    function getVrfCallbackGasLimit() external view returns (uint32) {
        return i_vrfCallbackGasLimit;
    }

    function getPlayer(uint256 index) external view returns (address) {
        return s_rafflePlayers[index];
    }

    function getAllPlayers() external view returns (address payable[] memory) {
        return s_rafflePlayers;
    }

    function getNumberOfPlayers() external view returns (uint256) {
        return s_rafflePlayers.length;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getRaffleOpenTimeStamp() external view returns (uint256) {
        return s_raffleOpenTimeStamp;
    }

    function getVrfRequestId() external view returns (uint256) {
        return s_vrfRequestId;
    }

    function getLastWinner() external view returns (address) {
        return s_lastWinner;
    }

    modifier onlyOwnerMayCall() {
        if (msg.sender != i_raffleContractOwner) {
            revert Raffle__NotOwner(msg.sender);
        }
        _;
    }
}
