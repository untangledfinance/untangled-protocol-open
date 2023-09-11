// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ICommandData, MessageType} from '../ICommandData.sol';

abstract contract CCIPReceiverStorageV2 {
    event MessageReceived(bytes32 indexed messageId, uint64 indexed sourceChainSelector, address sender, bytes data);

    error BridgeRouterExecutedFailed(MessageType messageType, bytes data);

    address untangledBridgeRouter;
    bytes32 public lastReceivedMessageId;
    ICommandData public lastReceivedData;
    mapping(bytes32 => ICommandData) public messageDataGroup;
    mapping(bytes32 => ICommandData) public failedMessageDataGroup;

    uint256 test;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}
