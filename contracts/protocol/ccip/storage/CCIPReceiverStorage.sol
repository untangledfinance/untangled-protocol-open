// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ICommandData} from '../ICommandData.sol';

abstract contract CCIPReceiverStorage {
    event MessageReceived(bytes32 indexed messageId, uint64 indexed sourceChainSelector, address sender, bytes data);

    address untangledBridgeRouter;
    bytes32 public lastReceivedMessageId;
    ICommandData public lastReceivedData;
    mapping(bytes32 => ICommandData) public messageDataGroup;
}
