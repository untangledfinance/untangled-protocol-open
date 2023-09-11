// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {OwnerIsCreator} from '@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol';
import {Client} from '@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol';
import {LinkTokenInterface} from '@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol';
import {IRouterClient} from '@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol';
import {CCIPSenderStorage} from './storage/CCIPSenderStorage.sol';

import {ICommandData} from './ICommandData.sol';

import {UntangledBase} from '../../base/UntangledBase.sol';

/// @title - A simple contract for sending string data across chains.
contract UntangledSender is UntangledBase, CCIPSenderStorage {
    // Custom errors to provide more descriptive revert messages.
    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees); // Used to make sure contract has enough balance.

    function initialize(IRouterClient router_, LinkTokenInterface link_) public initializer {
        __UntangledBase__init_unchained(_msgSender());
        __UntangledSender_init_unchained(router_, link_);
    }

    function __UntangledSender_init_unchained(
        IRouterClient router_,
        LinkTokenInterface link_
    ) internal onlyInitializing {
        router = router_;
        linkToken = link_;
    }

    /// @notice Sends data to receiver on the destination chain.
    /// @dev Assumes your contract has sufficient LINK.
    /// @param destinationChainSelector The identifier (aka selector) for the destination blockchain.
    /// @param receiver The address of the recipient on the destination blockchain.
    /// @return messageId The ID of the message that was sent.
    /// example: chainIdCode, UntangledReceiver, sig of hello
    function sendMessage(
        uint64 destinationChainSelector,
        address receiver,
        ICommandData calldata data,
        uint256 gasLimit
    ) external returns (bytes32 messageId) {
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver), // ABI-encoded receiver address
            data: abi.encode(data), // ABI-encoded struct
            tokenAmounts: new Client.EVMTokenAmount[](0), // Empty array indicating no tokens are being sent
            extraArgs: Client._argsToBytes(
                // Additional arguments, setting gas limit and non-strict sequencing mode
                Client.EVMExtraArgsV1({gasLimit: gasLimit, strict: false})
            ),
            // Set the feeToken  address, indicating LINK will be used for fees
            feeToken: address(linkToken)
        });

        // Get the fee required to send the message
        uint256 fees = router.getFee(destinationChainSelector, evm2AnyMessage);

        if (fees > linkToken.balanceOf(address(this))) {
            revert NotEnoughBalance(linkToken.balanceOf(address(this)), fees);
        }

        // approve the Router to transfer LINK tokens on contract's behalf. It will spend the fees in LINK
        linkToken.approve(address(router), fees);

        // Send the message through the router and store the returned message ID
        messageId = router.ccipSend(destinationChainSelector, evm2AnyMessage);

        // Emit an event with message details
        emit MessageSent(messageId, destinationChainSelector, receiver, data, address(linkToken), fees);

        // Return the message ID
        return messageId;
    }
}
