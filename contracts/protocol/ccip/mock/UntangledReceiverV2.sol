// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Client} from '@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol';
import {IAny2EVMMessageReceiver} from '@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol';

import {CCIPReceiverUpgradeable} from '../chainlink-upgradeable/CCIPReceiverUpgradeable.sol';
import {ICommandData} from '../ICommandData.sol';
import '../../../base/UntangledBase.sol';
import {CCIPReceiverStorageV2} from './CCIPReceiverStorageV2.sol';

contract UntangledReceiverV2 is UntangledBase, CCIPReceiverUpgradeable, CCIPReceiverStorageV2 {
    function initialize(address router) public initializer {
        __UntangledBase__init_unchained(_msgSender());
        __CCIPReceiver__init_unchained(router);
    }

    /// handle a received message
    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage) internal override {
        lastReceivedMessageId = any2EvmMessage.messageId;
        lastReceivedData = abi.decode(any2EvmMessage.data, (ICommandData));

        emit MessageReceived(
            any2EvmMessage.messageId,
            any2EvmMessage.sourceChainSelector,
            abi.decode(any2EvmMessage.sender, (address)),
            any2EvmMessage.data
        );

        // execute external contract, no exception
        // Address.functionCallWithValue(lastReceivedData.target, lastReceivedData.data);
    }

    function getLastReceivedMessageDetails() external view returns (bytes32 messageId, ICommandData memory command) {
        return (lastReceivedMessageId, lastReceivedData);
    }

    function hello() public pure returns (string memory greeting) {
        return 'Hello world';
    }

    function supportsInterface(bytes4 interfaceId)
        public
        pure
        override(AccessControlUpgradeable, CCIPReceiverUpgradeable)
        returns (bool)
    {
        return
            interfaceId == type(IAny2EVMMessageReceiver).interfaceId ||
            interfaceId == type(IERC165Upgradeable).interfaceId;
    }
}
