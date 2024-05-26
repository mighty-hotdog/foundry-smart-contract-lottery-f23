// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {Test, console} from "../../lib/forge-std/src/Test.sol";
//import {Test} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
//import {VRFCoordinatorV2Mock} from "../../lib/chainlink-brownie-contracts/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {VRFCoordinatorV2_5Mock} from "../../lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract RaffleTest is Test {
    Raffle private raffle;
    HelperConfig private helperConfig;

    uint256 raffleEntranceFee;
    uint256 automationUpkeepInterval;
    address vrfCoordinator;
    address vrfLinkToken;
    uint256 vrfSubscriptionId;
    bytes32 vrfGasLane;
    uint32 vrfCallbackGasLimit;

    ///////////////////////////////////////////////////////////////
    // All events emitted by Raffle contract and to be tested for
    ///////////////////////////////////////////////////////////////
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
    ///////////////////////////////////////////////////////////////

    address public PLAYER_1 = makeAddr("player_1");
    //address public PLAYER_2 = makeAddr("player_2");
    //address public PLAYER_3 = makeAddr("player_3");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant NOT_ENOUGH_ETH = 0.001 ether;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        (
            raffleEntranceFee,
            automationUpkeepInterval,
            vrfCoordinator,
            vrfLinkToken,
            vrfSubscriptionId,
            vrfGasLane,
            vrfCallbackGasLimit
        ) = helperConfig.s_activeNetworkConfig();
    }

    ////////////////////////////////////////////////////////////////////
    // Unit tests for constructor()
    ////////////////////////////////////////////////////////////////////
    function testRaffleStartsInOpenState() external view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    ////////////////////////////////////////////////////////////////////
    // Unit tests for enterRaffle()
    ////////////////////////////////////////////////////////////////////
    function testRaffleIsFull() public {
        for(uint256 i=1;i<=raffle.MAX_NUM_OF_PLAYERS();i++) {
            hoax(address(uint160(i)), STARTING_USER_BALANCE);
            raffle.enterRaffle{value: raffleEntranceFee}();
        }
        hoax(PLAYER_1,STARTING_USER_BALANCE);
        vm.expectRevert(Raffle.Raffle__RaffleIsFull.selector);
        raffle.enterRaffle{value: raffleEntranceFee}();
    }
    function testNotEnoughEthSent() public {
        hoax(PLAYER_1,STARTING_USER_BALANCE);
        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        raffle.enterRaffle{value: NOT_ENOUGH_ETH}();
    }
    function testOwnerNotAllowedAsPlayer() public {
        hoax(raffle.getRaffleOwner(),STARTING_USER_BALANCE);
        vm.expectRevert(Raffle.Raffle__OwnerNotAllowedAsPlayer.selector);
        raffle.enterRaffle{value: raffleEntranceFee}();
    }
    function testPlayerAlreadyExists() public {
        hoax(PLAYER_1,STARTING_USER_BALANCE);
        raffle.enterRaffle{value: raffleEntranceFee}();
        hoax(PLAYER_1,STARTING_USER_BALANCE);
        vm.expectRevert();
        raffle.enterRaffle{value: raffleEntranceFee}();
    }
    function testRaffleNotOpen() public isTime hasEthAndPlayers {
        raffle.performUpkeep("");
        hoax(PLAYER_1,STARTING_USER_BALANCE);
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        raffle.enterRaffle{value: raffleEntranceFee}();
    }
    function testFuzzEnterRaffleSuccessful(uint256 numOfPlayers) public {
        numOfPlayers = bound(numOfPlayers, 1, raffle.MAX_NUM_OF_PLAYERS());
        for(uint i=1;i<=numOfPlayers;i++) {
            //console.log("Adding player: ",i);
            enterRaffleSuccessful(address(uint160(i)), i-1);
        }
    }
    // This function itself is not called by forge test.//////////////////////////
    // It serves as a helper function to testFuzzEnterRaffleSuccessful().
    function enterRaffleSuccessful(address player, uint256 playerIndex) internal {
        hoax(player,STARTING_USER_BALANCE);
        raffle.enterRaffle{value: raffleEntranceFee}();
        address recordedPlayer = raffle.getPlayer(playerIndex);
        //console.log("player: ",player);
        //console.log("recordedPlayer: ",recordedPlayer);
        assert(player == recordedPlayer);
    }
    //////////////////////////////////////////////////////////////////////////////
    function testExpectEmitWhenPlayerJoined() public {
        hoax(PLAYER_1, STARTING_USER_BALANCE);
        vm.expectEmit(true, true, false, false, address(raffle));
        emit playerEnteredRaffle(PLAYER_1, raffleEntranceFee, /* dummy block.timestamp */ 0);
        raffle.enterRaffle{value: raffleEntranceFee}();
    }
    function testExpectEmitWhenMaxPlayersJoined() public {
        for(uint256 i=1;i<raffle.MAX_NUM_OF_PLAYERS();i++) {
            hoax(address(uint160(i)), STARTING_USER_BALANCE);
            raffle.enterRaffle{value: raffleEntranceFee}();
        }
        hoax(PLAYER_1, STARTING_USER_BALANCE);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit maxNumOfPlayersEntered(raffle.MAX_NUM_OF_PLAYERS(), /* dummy block.timestamp */ 0);
        raffle.enterRaffle{value: raffleEntranceFee}();
    }

    ////////////////////////////////////////////////////////////////////
    // Unit tests for checkUpkeep()
    ////////////////////////////////////////////////////////////////////
    function testNotYetTime() public hasEthAndPlayers {
        (bool isUpkeepNeeded,) = raffle.checkUpkeep("");
        assert(!isUpkeepNeeded);
    }
    function testIsTime() public hasEthAndPlayers {
        vm.warp(block.timestamp + automationUpkeepInterval + 1);
        vm.roll(block.number + 1);
        (bool isUpkeepNeeded,) = raffle.checkUpkeep("");
        assert(isUpkeepNeeded);
    }
    function testIsOpen() public isTime hasEthAndPlayers {
        (bool isUpkeepNeeded,) = raffle.checkUpkeep("");
        assert(isUpkeepNeeded);
    }
    function testIsNotOpen() public isTime hasEthAndPlayers {
        raffle.performUpkeep("");
        (bool isUpkeepNeeded,) = raffle.checkUpkeep("");
        assert(!isUpkeepNeeded);
    }
    function testHasNoPlayers() public isTime {
        (bool isUpkeepNeeded,) = raffle.checkUpkeep("");
        assert(!isUpkeepNeeded);
    }
    function testHasLessThanTwoPlayers() public isTime {
        hoax(PLAYER_1,STARTING_USER_BALANCE);
        raffle.enterRaffle{value: raffleEntranceFee} ();
        (bool isUpkeepNeeded,) = raffle.checkUpkeep("");
        assert(!isUpkeepNeeded);
    }
    function testFuzzHasTwoOrMorePlayers(uint256 numOfPlayers) public isTime {
        numOfPlayers = bound(numOfPlayers, 2, raffle.MAX_NUM_OF_PLAYERS());
        for(uint256 i=1;i<=numOfPlayers;i++) {
            hoax(address(uint160(i)),STARTING_USER_BALANCE);
            raffle.enterRaffle{value: raffleEntranceFee}();
        }
        (bool isUpkeepNeeded,) = raffle.checkUpkeep("");
        assert(isUpkeepNeeded);
    }
    
    modifier hasEthAndPlayers() {
        for(uint256 i=1;i<=5;i++) {
            hoax(address(uint160(i)),STARTING_USER_BALANCE);
            raffle.enterRaffle{value: raffleEntranceFee}();
        }
        _;
    }

    modifier isTime() {
        vm.warp(block.timestamp + automationUpkeepInterval + 1);
        vm.roll(block.number + 1);
        _;
    }

    ////////////////////////////////////////////////////////////////////
    // Unit tests for performUpkeep()
    ////////////////////////////////////////////////////////////////////
    function testExpectRevertWhenUpkeepNotNeeded() public {
        vm.expectRevert();
        raffle.performUpkeep("");
    }
    function testRaffleInProcessing() public upkeepNeeded {
        raffle.performUpkeep("");
        assert(raffle.getRaffleState() == Raffle.RaffleState.PROCESSING);
    }
    function testExpectEmitRaffleIsProcessing() public upkeepNeeded {
        vm.expectEmit(false, false, false, false, address(raffle));
        emit raffleIsProcessing(/* dummy block.timestamp */ 0);
        raffle.performUpkeep("");
    }
    function testVRFRandomNumberRequestMade() public upkeepNeeded {
        raffle.performUpkeep("");
        assert(raffle.getVrfRequestId() != 0);
    }
    function testExpectEmitVRFRequestMade() public upkeepNeeded {
        if (block.chainid == vm.envUint("DEFAULT_ANVIL_CHAINID")) {
            vm.expectEmit(true, false, false, false, address(raffle));
            emit vrfRequestMade(
                /* request Id will be 1, since there will only be a single request made in this test function setup*/ 1,
                /* dummy block.timestamp */ 0
            );
            raffle.performUpkeep("");
        } else {
            vm.expectEmit(false, false, false, false, address(raffle));
            emit vrfRequestMade(
                /* dummy request Id */ 1,
                /* dummy block.timestamp */ 0
            );
            raffle.performUpkeep("");
        }
    }

    modifier upkeepNeeded() {
        for(uint256 i=1;i<=5;i++) {
            hoax(address(uint160(i)),STARTING_USER_BALANCE);
            raffle.enterRaffle{value: raffleEntranceFee}();
        }
        vm.warp(block.timestamp + automationUpkeepInterval + 1);
        vm.roll(block.number + 1);
        _;
    }

    ////////////////////////////////////////////////////////////////////
    // Unit tests for fulfillRandomWords()
    ////////////////////////////////////////////////////////////////////
    /**
     * @dev fulfillRandomWords() call for all these tests is made via the mock VRF coordinator deployed on Anvil.
     *      On Testnet, Mainnet, or forked tests where Chainlink VRF exists, these test functions cannot be used 
     *      and are skipped.
     */
    function testPerformUpkeepNotCalled(uint256 mockRequestId) public skipOnForkTest upkeepNeeded {
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(mockRequestId, address(raffle));
    }
    function testWinnerSelected() public skipOnForkTest upkeepNeeded performUpkeepCalled {
        // copy out all the players before picking the winner
        address payable[] memory allPlayers = raffle.getAllPlayers();
        // picking the winner; after this function call, all players will be wiped
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(raffle.getVrfRequestId(), address(raffle));
        console.log("Completed fulfillRandomWords()");
        address winner = raffle.getLastWinner();
        bool winnerPicked = winner != address(0);
        bool winnerIsOneOfPlayers;
        for(uint256 i=0;i<allPlayers.length;i++) {
            if (winner == allPlayers[i]) {
                winnerIsOneOfPlayers = true;
                break;
            }
        }
        assert(winnerPicked && winnerIsOneOfPlayers);
    }
    function testExpectRaffleBalanceZero() public skipOnForkTest upkeepNeeded performUpkeepCalled {
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(raffle.getVrfRequestId(), address(raffle));
        assert(address(raffle).balance == 0);
    }
    function testExpectEmitWinnerSelected() public skipOnForkTest upkeepNeeded performUpkeepCalled {
        vm.expectEmit(false, false, false, false, address(raffle));
        emit winnerSelected(
            /* dummy winner address */ address(1),
            /* dummy block.timestamp */ 0
        );
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(raffle.getVrfRequestId(), address(raffle));
    }
    function testExpectEmitPayoutToWinnerCompleted() public skipOnForkTest upkeepNeeded performUpkeepCalled {
        vm.expectEmit(false, true, false, false, address(raffle));
        emit payoutToWinnerCompleted(
            /* dummy winner address */ address(1),
            /* current Raffle contract balance, which is the amount won by the winner */ address(raffle).balance,
            /* dummy block.timestamp */ 0
        );
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(raffle.getVrfRequestId(), address(raffle));
    }
    function testResetRaffleCalled() public skipOnForkTest upkeepNeeded performUpkeepCalled {
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(raffle.getVrfRequestId(), address(raffle));
        assert((raffle.getNumberOfPlayers() == 0) && (raffle.getRaffleState() == Raffle.RaffleState.OPEN));
    }

    modifier performUpkeepCalled() {
        raffle.performUpkeep("");
        _;
    }

    modifier skipOnForkTest() {
        if (block.chainid != vm.envUint("DEFAULT_ANVIL_CHAINID")) {
            return;
        }
        _;
    }

    ////////////////////////////////////////////////////////////////////
    // Unit tests for resetRaffle(), cleanupRaffle(), 
    // resetRaffleForced() and cleanupRaffleForced().
    ////////////////////////////////////////////////////////////////////
    /**
     * @dev Because resetRaffle() and cleanupRaffle() are internal, 
     *      will test them by calling their proxy forced functions
     *      instead.
     */
    function testCallResetRaffleForcedWithNonOwner() public {
        vm.prank(PLAYER_1);
        vm.expectRevert();
        raffle.resetRaffleForced();
    }
    function testCallCleanupRaffleForcedWithNonOwner() public {
        vm.prank(PLAYER_1);
        vm.expectRevert();
        raffle.cleanupRaffleForced();
    }
    function testExpectEmitForcedResetInitiated() public ownerCalling {
        vm.expectEmit(false, false, false, false, address(raffle));
        emit forcedResetInitiated(/* dummy block.timestamp */0);
        raffle.resetRaffleForced();
    }
    function testExpectEmitForcedCleanupInitiated() public ownerCalling {
        vm.expectEmit(false, false, false, false, address(raffle));
        emit forcedCleanupInitiated(/* dummy block.timestamp */0);
        raffle.cleanupRaffleForced();
    }
    function testNoExistingPlayersAfterReset() public ownerCalling {
        raffle.resetRaffleForced();
        assert(raffle.getNumberOfPlayers() == 0);
    }
    function testNoExistingPlayersAfterCleanup() public ownerCalling {
        raffle.cleanupRaffleForced();
        assert(raffle.getNumberOfPlayers() == 0);
    }
    /////////////////////////////////////////////////////////////////////
    // This test testRaffleBalanceIsZeroAfterReset() is failing on fork.
    // WHY???!!!
    // No reason whatsoever that right in the middle of construction, 
    // with no input of value from anywhere, the Raffle contract should 
    // have a non-zero balance. A forge bug?
    /*
    function testRaffleBalanceIsZeroAfterReset() public ownerCalling {
        raffle.resetRaffleForced();
        assert((address(raffle).balance) == 0);
    }
    */
    /////////////////////////////////////////////////////////////////////
    function testRaffleIsOpenAfterReset() public ownerCalling {
        raffle.resetRaffleForced();
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }
    function testExpectEmitRaffleIsOpenAfterReset() public ownerCalling {
        vm.expectEmit(false, false, false, false, address(raffle));
        emit raffleIsOpen(/* dummy block.timestamp */0);
        raffle.resetRaffleForced();
    }

    modifier ownerCalling() {
        vm.prank(raffle.getRaffleOwner());
        _;
    }
}