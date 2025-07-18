// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RebaseToken
 * @author WhatFate
 * @notice Cross-chain rebase token incentivizing vault deposits through rewards.
 * @notice Interest rate can only decrease.
 * @notice Each user inherits the global interest rate at deposit time.
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
    // --- Errors ---
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 oldInterestRate, uint256 newInterestRate);
    error RebaseToken__FutureTimeMustBeHigherThanCurrentTime();

    // --- Constants ---
    uint256 private constant PRECISION_FACTOR = 1e18;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");

    // --- State Variables ---
    uint256 private s_interestRate = (5 * PRECISION_FACTOR) / 1e8;
    mapping(address => uint256) private s_userInterestRates;
    mapping(address => uint256) private s_userLastUpdatedTimestamps;

    // --- Events ---
    event InterestRateUpdated(uint256 newInterestRate);
    event TokensMinted(address indexed to, uint256 amount, uint256 interestRate);
    event TokensBurned(address indexed from, uint256 amount);
    event AccruedInterestMinted(address indexed user, uint256 amount);

    /**
     * @notice Returns the current protocol interest rate
     */
    constructor() ERC20("Rebase Token", "RT") Ownable(msg.sender) {}

    // --- External View Functions ---

    /**
     * @notice Get the interest rate that is currently set for the contract. Any future depositors will receive this interest rate
     * @return The interest rate for the protocol
     */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }

    /**
     * @notice Get the principal balance of a user.
     *         This is the number of tokens that have currently been minted to the user,
     *         not including any interest that has accrued since the last time the user
     *         interacted with the protocol.
     * @param _user The address of the user
     * @return The principal balance of the user
     */
    function principalBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    /**
     * @notice Get the interest rate for a specific user
     * @param _user The address of the user
     * @return The interest rate for the user
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRates[_user];
    }

    /**
     * @notice Simulate user's balance at a future timestamp, assuming no interaction occurs
     * @dev Useful for frontend or analytics display
     * @param _user The address of the user
     * @param futureTime A future UNIX timestamp in seconds (must be >= block.timestamp)
     * @return The predicted balance including accrued interest
     */
    function simulateBalance(address _user, uint256 futureTime) external view returns (uint256) {
        if (futureTime <= block.timestamp) {
            revert RebaseToken__FutureTimeMustBeHigherThanCurrentTime();
        }
        uint256 delta  = futureTime - s_userLastUpdatedTimestamps[_user];
        uint256 rate = s_userInterestRates[_user];
        uint256 principal = super.balanceOf(_user);

        uint256 interest = delta * rate;
        uint256 simulated = principal * (PRECISION_FACTOR + interest) / PRECISION_FACTOR;
        
        return simulated;
    }

    // --- Public Overrides ---

    /**
     * @notice Calculate the balance for the user including the interest that has accumulated since the last update
     * @param _user The address of the user
     * @return The balance of the user
     */
    function balanceOf(address _user) public view override returns (uint256) {
        uint256 principal = super.balanceOf(_user);
        uint256 factor = _calculateInterestFactor(_user);
        return principal * factor / PRECISION_FACTOR;
    }

    /**
     * @notice Transfer tokens from one user to another
     * @param _recipient The address of the recipient
     * @param _amount The amount of tokens to transfer
     * @return True if the transfer was successful
     */
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        _accrueInterest(msg.sender);
        _accrueInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        if (balanceOf(_recipient) == 0) {
            s_userInterestRates[_recipient] = s_userInterestRates[msg.sender];
        }
        return super.transfer(_recipient, _amount);
    }

    /**
     * @notice Transfer tokens from one user to another
     * @param _sender The address of the sender
     * @param _recipient The address of the recipient
     * @param _amount The amount of tokens to transfer
     * @return True if the transfer was successful
     */
    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _accrueInterest(_sender);
        _accrueInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }
        if (balanceOf(_recipient) == 0) {
            s_userInterestRates[_recipient] = s_userInterestRates[_sender];
        }
        return super.transferFrom(_sender, _recipient, _amount);
    }

    // --- Restricted (Owner) Functions ---

    /**
     * @notice Grants mint and burn permissions to an account
     * @param _account The address of the account to grant permissions to
     * @dev This function can only be called by the contract owner
     */
    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /**
     * @notice Set the interest rate in the contract
     * @param _newInterestRate The new interest rate to be set
     * @dev The interest rate can only decrease
     */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        if (_newInterestRate >= s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateUpdated(_newInterestRate);
    }

    // --- Restricted (Role) Functions ---

    /**
     * @notice Mint the user tokens when they deposit into the vault
     * @param _to The address of the user
     * @param _amount The amount of tokens to mint
     */
    function mint(address _to, uint256 _amount, uint256 _userInterestRate) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRates[_to] = _userInterestRate;
        _mint(_to, _amount);
        emit TokensMinted(_to, _amount, _userInterestRate);
    }

    /**
     * @notice Burn the user tokens when they withdraw from the vault
     * @param _from The address of the user
     * @param _amount The amount of tokens to burn
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_from);
        }
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
        emit TokensBurned(_from, _amount);
    }

    // --- Internal Utilities ---

    /**
     * @dev Calculates interest factor since last update (scaled by PRECISION_FACTOR).
     * @param user The address of the user
     * @return The calculated interest factor
     */
    function _calculateInterestFactor(address user) internal view returns (uint256) {
        uint256 delta = block.timestamp - s_userLastUpdatedTimestamps[user];
        return PRECISION_FACTOR + (s_userInterestRates[user] * delta);
    }

    /**
     * @dev Mints accrued interest to user and updates timestamp.
     * @param user The address of the user
     */
    function _accrueInterest(address user) internal {
        uint256 principal = super.balanceOf(user);
        uint256 factor = _calculateInterestFactor(user);
        uint256 adjusted = principal * factor / PRECISION_FACTOR;
        uint256 interest = adjusted - principal;

        s_userLastUpdatedTimestamps[user] = block.timestamp;

        if (interest > 0) {
            _mint(user, interest);
            emit AccruedInterestMinted(user, interest);
        }
    }

    /**
     * @notice Calculate the accumulated interest for a user since their last update
     * @param _user The address of the user
     * @return linearInterest interest that has accumulated since the last update
     */
    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user) internal view returns (uint256 linearInterest) {
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamps[_user];
        linearInterest = PRECISION_FACTOR + (s_userInterestRates[_user] * timeElapsed);
    }

    /**
     * @notice Mint the accrued interest to the user since the last time they interacted with the protocol (e.g., burn, mint, transfer)
     * @param _user The user to mint the accrued interest to
     */
    function _mintAccruedInterest(address _user) internal {
        uint256 previousPrincipleBalance = super.balanceOf(_user);
        uint256 currentBalance = balanceOf(_user);
        uint256 balanceIncrease = currentBalance - previousPrincipleBalance;  
        s_userLastUpdatedTimestamps[_user] = block.timestamp;
        _mint(_user, balanceIncrease);
        emit AccruedInterestMinted(_user, balanceIncrease);
    }
}