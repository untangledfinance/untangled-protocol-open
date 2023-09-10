// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Client} from '@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol';
import {IAny2EVMMessageReceiver} from '@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol';

import {CCIPReceiverUpgradeable} from './chainlink-upgradeable/CCIPReceiverUpgradeable.sol';
import {ICommandData} from './ICommandData.sol';
import '../../base/UntangledBase.sol';
import {CCIPReceiverStorage} from './storage/CCIPReceiverStorage.sol';

/// @title - A simple contract for receiving string data across chains.
contract UntangedReceiver is UntangledBase, CCIPReceiverUpgradeable, CCIPReceiverStorage {
    function initialize(address router) public initializer {
        __UntangledBase__init_unchained(_msgSender());
        __CCIPReceiver__init_unchained(router);
    }

    /// handle a received message
    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage) internal override {
        lastReceivedMessageId = any2EvmMessage.messageId; // fetch the messageId
        lastReceivedData = abi.decode(any2EvmMessage.data, (ICommandData)); // abi-decoding of the sent text

        emit MessageReceived(
            any2EvmMessage.messageId,
            any2EvmMessage.sourceChainSelector, // fetch the source chain identifier (aka selector)
            abi.decode(any2EvmMessage.sender, (address)), // abi-decoding of the sender address,
            any2EvmMessage.data
        );

        // execute external contract, no exception
        // Address.functionCallWithValue(lastReceivedData.target, lastReceivedData.data);
    }

    /// @notice Fetches the details of the last received message.
    function getLastReceivedMessageDetails() external view returns (bytes32 messageId, ICommandData memory command) {
        return (lastReceivedMessageId, lastReceivedData);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        pure
        override(AccessControlEnumerableUpgradeable, CCIPReceiverUpgradeable)
        returns (bool)
    {
        return
            interfaceId == type(IAny2EVMMessageReceiver).interfaceId ||
            interfaceId == type(IERC165Upgradeable).interfaceId;
    }
}
