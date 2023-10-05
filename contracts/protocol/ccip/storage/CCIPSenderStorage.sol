// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ICommandData, MessageType} from '../ICommandData.sol';
import {IRouterClient} from '@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol';
import {LinkTokenInterface} from '@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol';
import {ICommandData} from '../ICommandData.sol';

abstract contract CCIPSenderStorage {
    // Event emitted when a message is sent to another chain.
    event MessageSent(
        bytes32 indexed messageId, // The unique ID of the CCIP message.
        uint64 indexed destinationChainSelector, // The chain selector of the destination chain.
        address receiver, // The address of the receiver on the destination chain.
        ICommandData data, // The text being sent.
        address feeToken, // the token address used to pay CCIP fees.
        uint256 fees // The fees paid for sending the CCIP message.
    );

    event UpdateWhitelistSelector(MessageType indexed target, bytes4 indexed functionSignature, bool isAllow);

    IRouterClient public router;
    LinkTokenInterface public linkToken;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
