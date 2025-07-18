// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title BridgeTokensScript
 * @notice This script facilitates sending tokens across blockchain network using the CCIP (Cross-Chain Interoperability Protocol).
 * @dev This contract leverages Foundry's Script functionality for deployment and execution, using LINK tokens to pay fees.
 */
contract BridgeTokensScript is Script {
    error BridgeTokens__InvalidAddresses();
    error BridgeTokens__InvalidAmount();
    error BridgeTokens__InvalidDestinationChain();
    error BridgeTokens__InsufficientBalance();

    /**
     * @notice Executes the token bridging process using CCIP.
     * @param receiverAddress The address on the destination chain that will receive the tokens.
     * @param tokenToSendAddress The address of the ERC20 token to be transferred.
     * @param amountToSend The amount of tokens to send (must be greater than zero).
     * @param linkTokenAddress The address of the LINK token used to pay CCIP fees.
     * @param routerAddress The address of the CCIP router contract.
     * @param destinationChainSelector The unique identifier of the destination blockchain.
     * @dev Validates inputs, calculates fees, checks balances, approves tokens, and sends the CCIP transaction.
     */
    function run(
        address receiverAddress,
        address tokenToSendAddress,
        uint256 amountToSend,
        address linkTokenAddress,
        address routerAddress,
        uint64 destinationChainSelector
    ) external {
        if (receiverAddress == address(0) || tokenToSendAddress == address(0) || linkTokenAddress == address(0) || routerAddress == address(0)) {
            revert BridgeTokens__InvalidAddresses();
        }

        if (amountToSend == 0) revert BridgeTokens__InvalidAmount();
        if (destinationChainSelector == 0) revert BridgeTokens__InvalidDestinationChain();

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: tokenToSendAddress,
            amount: amountToSend
        });

        uint256 ccipFee = IRouterClient(routerAddress).getFee(destinationChainSelector, _buildMessage(receiverAddress, tokenAmounts, linkTokenAddress));
        if (IERC20(linkTokenAddress).balanceOf(msg.sender) < ccipFee) revert BridgeTokens__InsufficientBalance();
        if (IERC20(tokenToSendAddress).balanceOf(msg.sender) < amountToSend) revert BridgeTokens__InsufficientBalance();

        vm.startBroadcast();
        _approveTokens(routerAddress, tokenToSendAddress, amountToSend, linkTokenAddress, ccipFee);
        IRouterClient(routerAddress).ccipSend(destinationChainSelector, _buildMessage(receiverAddress, tokenAmounts, linkTokenAddress));
        vm.stopBroadcast();
    }

    /**
     * @notice Constructs a CCIP message for token transfer.
     * @param receiverAddress The address that will receive the tokens on the destination chain.
     * @param tokenAmounts An array specifying the tokens and amounts to be sent.
     * @param linkTokenAddress The address of the LINK token used for fee payment.
     * @return A Client.EVM2AnyMessage struct containing the encoded message details.
     * @dev This function is internal and pure, meaning it does not modify state and only uses input parameters.
     */
    function _buildMessage(
        address receiverAddress,
        Client.EVMTokenAmount[] memory tokenAmounts,
        address linkTokenAddress
    ) internal pure returns (Client.EVM2AnyMessage memory) {
        return Client.EVM2AnyMessage({
            receiver: abi.encode(receiverAddress),
            data: "",
            tokenAmounts: tokenAmounts,
            feeToken: linkTokenAddress,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0}))
        });
    }

    /**
     * @notice Approves the CCIP router to spend tokens on behalf of the sender.
     * @param routerAddress The address of the CCIP router contract.
     * @param tokenToSendAddress The address of the ERC20 token to send.
     * @param amountToSend The amount of tokens to approve for transfer.
     * @param linkTokenAddress The address of the LINK token used for fees.
     * @param ccipFee The amount of LINK tokens required for the CCIP fee.
     * @dev Checks existing allowances and updates them if necessary for both the token and LINK.
     */
    function _approveTokens(
        address routerAddress,
        address tokenToSendAddress,
        uint256 amountToSend,
        address linkTokenAddress,
        uint256 ccipFee
    ) internal {
        if (IERC20(linkTokenAddress).allowance(msg.sender, routerAddress) < ccipFee) {
            IERC20(linkTokenAddress).approve(routerAddress, ccipFee);
        }
        if (IERC20(tokenToSendAddress).allowance(msg.sender, routerAddress) < amountToSend) {
            IERC20(tokenToSendAddress).approve(routerAddress, amountToSend);
        }
    }
}
