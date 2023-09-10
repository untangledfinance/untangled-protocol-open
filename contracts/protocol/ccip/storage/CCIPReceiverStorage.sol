// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ICommandData} from '../ICommandData.sol';

abstract contract CCIPReceiverStorage {
    event MessageReceived(bytes32 indexed messageId, uint64 indexed sourceChainSelector, address sender, bytes data);

    bytes32 public lastReceivedMessageId;
    ICommandData public lastReceivedData;
}
