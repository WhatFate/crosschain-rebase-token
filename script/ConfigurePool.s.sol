// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {RateLimiter} from "@ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";

/**
 * @title ConfigurePoolScript
 * @notice This script configures a TokenPool for the Chainlink CCIP protocol.
 * @dev Deploys and configures a TokenPool to enable cross-chain token transfers with rate limiting.
 *      Intended to be executed using Forge for simulation and deployment.
 */
contract ConfigurePoolScript is Script {
    /**
     * @notice Configures the TokenPool with remote chain details and rate limiters.
     * @param localPool Address of the TokenPool contract on the local chain.
     * @param remoteChainSelector Unique identifier for the remote chain (e.g., Chain ID).
     * @param allowed Boolean flag identifier if the remote chain is allowed to interact.
     * @param remotePool Address of the TokenPool contract on the remote chain.
     * @param remoteToken Address of the token contract on the remote chain.
     * @param outboundRateLimiterIsEnabled Enables/disables the outbound rate limiter.
     * @param outboundRateLimiterCapacity Maximum capacity for outbound token transfers.
     * @param outboundRateLimiterRate Refill rate for the outbound rate limiter.
     * @param inboundRateLimiterIsEnabled Enables/disables the inbound rate limiter.
     * @param inboundRateLimiterCapacity Maximum capacity for inbound token transfers.
     * @param inboundRateLimiterRate Refill rate for the inbound rate limiter.
     * @dev The function uses 'vm.broadcast' to simulate transaction execution.
     *      Ensure the caller has appropriate permissions on the TokenPool.
     */
    function run(
        address localPool,
        uint64 remoteChainSelector,
        bool allowed,
        address remotePool,
        address remoteToken,
        bool outboundRateLimiterIsEnabled,
        uint128 outboundRateLimiterCapacity,
        uint128 outboundRateLimiterRate,
        bool inboundRateLimiterIsEnabled,
        uint128 inboundRateLimiterCapacity,
        uint128 inboundRateLimiterRate
    ) public {
        vm.startBroadcast();

        // --- Prepare remote pool address encoding ---
        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = abi.encode(remotePool);
        
        // --- Construct chain update configuration ---
        TokenPool.ChainUpdate[]
            memory chainsToAdd = new TokenPool.ChainUpdate[](1);
        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            allowed: allowed,
            remotePoolAddress: abi.encode(remotePoolAddresses),
            remoteTokenAddress: abi.encode(remoteToken),
            outboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: outboundRateLimiterIsEnabled,
                capacity: outboundRateLimiterCapacity,
                rate: outboundRateLimiterRate
            }),
            inboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: inboundRateLimiterIsEnabled,
                capacity: inboundRateLimiterCapacity,
                rate: inboundRateLimiterRate
            })
        });

        // --- Apply the configuration to the TokenPool ---
        TokenPool(localPool).applyChainUpdates(chainsToAdd);
        
        vm.stopBroadcast();
    }
}
