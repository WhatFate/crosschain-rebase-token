// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Vault Contract
 * @notice Allows users to deposit ETH to mint rebase tokens and redeem them for ETH.
 * @dev This contract uses a reentrancy guard to prevent reentrant calls.
 */
contract Vault is ReentrancyGuard {
    error Vault__InsufficientBalance();
    error Vault__ETHTransferFailed();

    IRebaseToken private immutable i_rebaseToken;

    event Deposit(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    /**
     * @notice Initializes the Vault with the rebase token contract address.
     * @param _rebaseToken Address of the rebase token contract.
     */
    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    /**
     * @notice Accepts ETH sent directly to the contract.
     */
    receive() external payable {}

    /**
     * @notice Deposit ETH into the vault and mint rebase tokens in return.
     */
    function deposit() external payable nonReentrant {
        uint256 interestRate = i_rebaseToken.getInterestRate();
        i_rebaseToken.mint(msg.sender, msg.value, interestRate);
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice Allows users to redeem their rebase tokens for ETH.
     * @param amount The amount of rebase tokens to redeem.
     */
    function redeem(uint256 amount) external {
        if (amount == 0 || amount > i_rebaseToken.balanceOf(msg.sender)) {
            revert Vault__InsufficientBalance();
        }
        _redeem(msg.sender, amount);
    }

    /**
     * @notice Redeems all user’s rebase tokens for ETH.
     */
    function redeemAll() external nonReentrant {
        uint256 balance = i_rebaseToken.balanceOf(msg.sender);
        if (balance == 0) revert Vault__InsufficientBalance();
        _redeem(msg.sender, balance);
    }

    /**
     * @notice Get the address of the rebase token contract.
     * @return Address of the rebase token contract.
     */
    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }

    /**
     * @notice Internal function to burn tokens and transfer ETH.
     * @param user Address of the user redeeming tokens.
     * @param amount Amount of tokens to burn and ETH to transfer.
     */
    function _redeem(address user, uint256 amount) internal {
        i_rebaseToken.burn(user, amount);
        (bool success, ) = payable(user).call{value: amount}("");
        if (!success) revert Vault__ETHTransferFailed();
        emit Redeem(user, amount);
    }
}