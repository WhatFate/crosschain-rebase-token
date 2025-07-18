// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/interfaces/IERC20.sol";
import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";

/**
 * @title Token And Pool Deployment Script
 * @notice Deploys a RebaseToken and associated RebaseTokenPool.
 */
contract TokenAndPoolDeployer is Script {
    
    /**
     * @notice Deploys RebaseToken and RebaseTokenPool contracts
     * @return token The deployed RebaseToken instance
     * @return pool The deployed RebaseTokenPool instance
     */
    function run() public returns (RebaseToken token, RebaseTokenPool pool) {
        CCIPLocalSimulatorFork ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        Register.NetworkDetails memory networkDetails = ccipLocalSimulatorFork
            .getNetworkDetails(block.chainid);

        vm.startBroadcast();

        token = new RebaseToken();
        pool = new RebaseTokenPool(
            IERC20(address(token)),
            new address[](0),
            networkDetails.rmnProxyAddress,
            networkDetails.routerAddress
        );

        vm.stopBroadcast();
    }
}

/**
 * @title Role and Permission Setup Script
 * @notice Grants roles and sets admin for the RebaseToken and RebaseTokenPool contracts
 */
contract setPermissions is Script {

    /**
     * @notice Grants mint and burn role to the pool
     * @param token Address of the RebaseToken contract
     * @param pool Address of the RebaseTokenPool contract
     */
    function grantRole(address token, address pool) public {
        vm.startBroadcast();
        IRebaseToken(token).grantMintAndBurnRole(address(pool));
        vm.stopBroadcast();
    }

    /**
     * @notice Registers admin and sets pool in TokenAdminRegistry
     * @param token Address of the RebaseToken contract
     * @param pool Address of the RebaseTokenPool contract
     */
    function setAdmin(address token, address pool) public {
        CCIPLocalSimulatorFork ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        Register.NetworkDetails memory networkDetails = ccipLocalSimulatorFork
            .getNetworkDetails(block.chainid);
        
        vm.startBroadcast();
        
        RegistryModuleOwnerCustom(
            networkDetails.registryModuleOwnerCustomAddress
        ).registerAdminViaOwner(address(token));
        TokenAdminRegistry(networkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(token));
        TokenAdminRegistry(networkDetails.tokenAdminRegistryAddress).setPool(
            address(token),
            address(pool)
        );

        vm.stopBroadcast();
    }
}

/**
 * @title Vault Deployment Script
 * @notice Deployes the Vault contract and grants mint/burn role
 */
contract VaultDeployer is Script {

    /**
     * @notice Deploys the Vault with the specified RebaseToken
     * @param _rebaseToken Address of the deployed RebaseToken
     * @return vault The deployed Vault instance
     */
    function run(address _rebaseToken) public returns (Vault vault) {
        vm.startBroadcast();
        
        vault = new Vault(IRebaseToken(_rebaseToken));
        IRebaseToken(_rebaseToken).grantMintAndBurnRole(address(vault));
        
        vm.stopBroadcast();
    }
}
