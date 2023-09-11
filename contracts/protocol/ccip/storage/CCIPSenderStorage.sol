// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

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
}
