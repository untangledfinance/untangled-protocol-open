// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ICommandData} from '../ICommandData.sol';

abstract contract CCIPReceiverStorage {
    event MessageReceived(bytes32 indexed messageId, uint64 indexed sourceChainSelector, address sender, bytes data);

    bytes32 public lastReceivedMessageId;
    ICommandData public lastReceivedData;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
