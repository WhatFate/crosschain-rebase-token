// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console, Test} from "forge-std/Test.sol";

import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";

import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

contract RebaseTokenTest is Test {
    error Vault__TransferFailed();

    RebaseToken public rebaseToken;
    Vault public vault;

    address public user = makeAddr("user");
    address public owner = makeAddr("owner");
    uint256 public SEND_VALUE = 1e5;

    /**
     * @notice Sends ETH to the Vault contract to fund rewards.
     * @dev Reverts with Vault__TransferFailed if the transfer fails.
     * @param amount The amount of ETH to send to the vault.
     */
    function addRewardsToVault(uint256 amount) public {
        (bool success, ) = payable(address(vault)).call{value: amount}("");
        if (!success) {
            revert Vault__TransferFailed();
        }
    }

    /**
     * @notice Initializes the RebaseToken and Vault contracts.
     * @dev Grants the Vault mint/burn roles on the RebaseToken.
     */
    function setUp() public {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        vm.stopPrank();
    }

    /**
     * @notice Tests that depositing ETH into the Vault increases token balance linearly over time.
     * @dev Simulates interest accrual over two hours and checks balance growth.
     * @param amount The amount of ETH to deposit.
     */
    function testDepositLinear(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();

        uint256 startBalance = rebaseToken.balanceOf(user);
        console.log("block.timestamp", block.timestamp);
        console.log("startBalance", startBalance);
        assertEq(startBalance, amount);

        vm.warp(block.timestamp + 1 hours);
        console.log("block.timestamp", block.timestamp);
        uint256 middleBalance = rebaseToken.balanceOf(user);
        console.log("middleBalance", middleBalance);
        assertGt(middleBalance, startBalance);

        vm.warp(block.timestamp + 1 hours);
        uint256 endBalance = rebaseToken.balanceOf(user);
        console.log("block.timestamp", block.timestamp);
        console.log("endBalance", endBalance);
        assertGt(endBalance, middleBalance);

        assertApproxEqAbs(endBalance - middleBalance, middleBalance - startBalance, 1);

        vm.stopPrank();
    }

    /**
     * @notice Tests immediate redemption of tokens after deposit.
     * @dev Verifies token balance becomes zero after instant redemption.
     * @param amount The amount of ETH to deposit and redeem.
     */
    function testRedeemStraightAway(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();

        vault.redeem(amount);

        uint256 balance = rebaseToken.balanceOf(user);
        console.log("User balance: %d", balance);
        assertEq(balance, 0);
        vm.stopPrank();
    }

    /**
     * @notice Tests redemption after interest has accrued over time.
     * @dev Deposits ETH, accrues interest, funds vault with extra ETH, then redeems.
     * @param depositAmount Initial deposit amount in ETH.
     * @param time Time (in seconds) to wait before redeeming.
     */
    function testRedeemAfterTimeHasPassed(uint256 depositAmount, uint256 time) public {
        time = bound(time, 1000, type(uint64).max);
        depositAmount = bound(depositAmount, 1e5, type(uint96).max);

        vm.deal(user, depositAmount);
        vm.prank(user);
        vault.deposit{value: depositAmount}();

        vm.warp(time);

        uint256 balance = rebaseToken.balanceOf(user);

        vm.deal(owner, balance - depositAmount);
        vm.prank(owner);
        addRewardsToVault(balance - depositAmount);

        vm.prank(user);
        vault.redeem(balance);

        uint256 ethBalance = address(user).balance;

        assertEq(balance, ethBalance);
        assertGt(balance, depositAmount);
    }

    /**
     * @notice Tests that unauthorized users cannot call mint().
     * @dev Should revert due to missing minting permission.
     */
    function testCannotCallMint() public {
        vm.startPrank(user);
        uint256 interestRate = rebaseToken.getInterestRate();
        vm.expectRevert();
        rebaseToken.mint(user, SEND_VALUE, interestRate);
        vm.stopPrank();
    }

    /**
     * @notice Tests that unauthorized users cannot call burn().
     * @dev Should revert due to missing burning permission.
     */
    function testCannotCallBurn() public {
        vm.startPrank(user);
        vm.expectRevert();
        rebaseToken.burn(user, SEND_VALUE);
        vm.stopPrank();
    }

    /**
     * @notice Tests that redeeming more tokens than owned reverts.
     * @dev Ensures vault prevents overdraft redemption attempts.
     */
    function testCannotWithdrawMoreThanBalance() public {
        vm.startPrank(user);
        vm.deal(user, SEND_VALUE);
        vault.deposit{value: SEND_VALUE}();
        vm.expectRevert();
        vault.redeem(SEND_VALUE + 1);
        vm.stopPrank();
    }

    /**
     * @notice Tests a basic deposit into the Vault.
     * @dev Verifies successful deposit call with a valid amount.
     * @param amount Amount of ETH to deposit.
     */
    function testDeposit(uint256 amount) public {
        amount = bound(amount, 1e3, type(uint96).max);
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();
    }

    /**
     * @notice Tests transferring tokens to another user and verifies interest accrual.
     * @dev Simulates token transfer and checks balances and interest rates post-transfer.
     * @param amount Initial ETH deposit amount.
     * @param amountToSend Amount of tokens to transfer to another user.
     */
    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 1e5 + 1e3, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e3);

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        address userTwo = makeAddr("userTwo");
        uint256 userBalance = rebaseToken.balanceOf(user);
        uint256 userTwoBalance = rebaseToken.balanceOf(userTwo);
        assertEq(userBalance, amount);
        assertEq(userTwoBalance, 0);

        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        vm.prank(user);
        rebaseToken.transfer(userTwo, amountToSend);
        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 userTwoBalanceAfterTransfer = rebaseToken.balanceOf(userTwo);
        assertEq(userBalanceAfterTransfer, userBalance - amountToSend);
        assertEq(userTwoBalanceAfterTransfer, amountToSend);

        vm.warp(block.timestamp + 1 days);
        uint256 userBalanceAfterWarp = rebaseToken.balanceOf(user);
        uint256 userTwoBalanceAfterWarp = rebaseToken.balanceOf(userTwo);

        uint256 userTwoInterestRate = rebaseToken.getUserInterestRate(userTwo);
        assertEq(userTwoInterestRate, 5e10);

        uint256 userInterestRate = rebaseToken.getUserInterestRate(user);
        assertEq(userInterestRate, 5e10);

        assertGt(userBalanceAfterWarp, userBalanceAfterTransfer);
        assertGt(userTwoBalanceAfterWarp, userTwoBalanceAfterTransfer);
    }

    /**
     * @notice Tests that only the owner can set a new interest rate.
     * @dev Also verifies that users get the new rate upon deposit.
     * @param newInterestRate The new interest rate to apply.
     */
    function testSetInterestRate(uint256 newInterestRate) public {
        newInterestRate = bound(newInterestRate, 0, rebaseToken.getInterestRate() - 1);

        vm.startPrank(owner);
        rebaseToken.setInterestRate(newInterestRate);
        uint256 interestRate = rebaseToken.getInterestRate();
        assertEq(interestRate, newInterestRate);
        vm.stopPrank();

        vm.startPrank(user);
        vm.deal(user, SEND_VALUE);
        vault.deposit{value: SEND_VALUE}();
        uint256 userInterestRate = rebaseToken.getUserInterestRate(user);
        vm.stopPrank();
        assertEq(userInterestRate, newInterestRate);
    }

    /**
     * @notice Tests that non-owners cannot change the interest rate.
     * @dev Function call must revert when called by a non-owner.
     * @param newInterestRate The attempted new rate (should not be applied).
     */
    function testCannotSetInterestRate(uint256 newInterestRate) public {
        vm.startPrank(user);
        vm.expectRevert();
        rebaseToken.setInterestRate(newInterestRate);
        vm.stopPrank();
    }

    /**
     * @notice Tests that the interest rate cannot be increased.
     * @dev Reverts if the new rate is greater than the current one.
     * @param newInterestRate The attempted new interest rate.
     */
    function testInterestRateCanOnlyDecrease(uint256 newInterestRate) public {
        uint256 initialInterestRate = rebaseToken.getInterestRate();
        newInterestRate = bound(newInterestRate, initialInterestRate, type(uint96).max);
        vm.prank(owner);
        vm.expectPartialRevert(bytes4(RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector));
        rebaseToken.setInterestRate(newInterestRate);
        assertEq(rebaseToken.getInterestRate(), initialInterestRate);
    }

    /**
     * @notice Tests that principal balance remains constant over time.
     * @dev Verifies that only accrued interest increases, not the principal.
     */
    function testGetPrincipleAmount() public {
        uint256 amount = 1e5;
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();
        uint256 principleAmount = rebaseToken.principalBalanceOf(user);
        assertEq(principleAmount, amount);

        vm.warp(block.timestamp + 1 days);
        uint256 principleAmountAfterWarp = rebaseToken.principalBalanceOf(user);
        assertEq(principleAmountAfterWarp, principleAmount);
    }
}

