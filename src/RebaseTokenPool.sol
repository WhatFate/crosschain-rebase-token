// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {Pool} from "@ccip/contracts/src/v0.8/ccip/libraries/Pool.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

/**
 * @title RebaseTokenPool
 * @notice Cross-chain token pool for interest-bearing rebase tokens
 * @dev Inherits from CCIP tokenPool and overrides lockOrBurn / releaseOrMint for custom logic
 */
contract RebaseTokenPool is TokenPool {

    /**
     * @notice Constructor for initializing the RebaseTokenPool
     * @param _token The ERC20 token to use (must support rebase minting/burning)
     * @param _allowlist Addresses allowed to interact with the pool
     * @param _rmnProxy Proxy address for RMN
     * @param _router Cross-chain router address
     */
    constructor(
        IERC20 _token, 
        address[] memory _allowlist, 
        address _rmnProxy, 
        address _router
    ) 
        TokenPool(_token, _allowlist, _rmnProxy, _router) 
    {}

    /**
     * @notice Called on source chain to burn tokens and encode user data
     * @dev Burns user's tokens and encodes their interest rate into destPoolData
     * @param lockOrBurnIn Struct containing sender address, amount, and destination chain info
     * @return lockOrBurnOut Encoded output including remote token address and user data
     */
    function lockOrBurn(Pool.LockOrBurnInV1 calldata lockOrBurnIn) 
        external 
        override
        returns (Pool.LockOrBurnOutV1 memory lockOrBurnOut) 
    {
        _validateLockOrBurn(lockOrBurnIn);
        uint256 userInterestRate = IRebaseToken(address(i_token)).getUserInterestRate(lockOrBurnIn.originalSender);
        IRebaseToken(address(i_token)).burn(address(this), lockOrBurnIn.amount);

        lockOrBurnOut = Pool.LockOrBurnOutV1({
            destTokenAddress:  getRemoteToken(lockOrBurnIn.remoteChainSelector),
            destPoolData: abi.encode(userInterestRate)
        });
    }

    /**
     * @notice Called on destination chain to mint tokens based on received data
     * @dev Mints tokens for the receiver using interest rate from source chain
     * @param releaseOrMintIn Struct containing receiver, amount, and encoded interest rate
     * @return releaseOrMintOut Struct indicating minted amount on destination chain
     */
    function releaseOrMint(Pool.ReleaseOrMintInV1 calldata releaseOrMintIn) 
        external 
        override
        returns (Pool.ReleaseOrMintOutV1 memory releaseOrMintOut) 
    {
        _validateReleaseOrMint(releaseOrMintIn);
        uint256 userInterestRate = abi.decode(releaseOrMintIn.sourcePoolData, (uint256));
        IRebaseToken(address(i_token)).mint(releaseOrMintIn.receiver, releaseOrMintIn.amount, userInterestRate);

        releaseOrMintOut = Pool.ReleaseOrMintOutV1({
            destinationAmount: releaseOrMintIn.amount
        });
    }
}