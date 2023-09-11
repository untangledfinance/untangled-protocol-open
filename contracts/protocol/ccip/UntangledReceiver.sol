// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Client} from '@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol';
import {IAny2EVMMessageReceiver} from '@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol';

import {CCIPReceiverUpgradeable} from './chainlink-upgradeable/CCIPReceiverUpgradeable.sol';
import {ICommandData} from './ICommandData.sol';
import '../../base/UntangledBase.sol';
import {CCIPReceiverStorage} from './storage/CCIPReceiverStorage.sol';
import {IUntangledBridgeRouter} from './interfaces/IUntangledBridgeRouter.sol';

contract UntangledReceiver is UntangledBase, CCIPReceiverUpgradeable, CCIPReceiverStorage {
    function initialize(address _router, address _untangledBridgeRouter) public initializer {
        __UntangledBase__init_unchained(_msgSender());
        __CCIPReceiver__init_unchained(_router);

        untangledBridgeRouter = _untangledBridgeRouter;
    }

    function setBridgeRouter(address _untangledBridgeRouter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        untangledBridgeRouter = _untangledBridgeRouter;
    }

    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage) internal override {
        lastReceivedMessageId = any2EvmMessage.messageId;
        lastReceivedData = abi.decode(any2EvmMessage.data, (ICommandData));
        messageDataGroup[lastReceivedMessageId] = lastReceivedData;

        emit MessageReceived(
            any2EvmMessage.messageId,
            any2EvmMessage.sourceChainSelector,
            abi.decode(any2EvmMessage.sender, (address)),
            any2EvmMessage.data
        );

        (bool success, ) = untangledBridgeRouter.call(
            abi.encodeWithSignature('processMessage(uint8,bytes)', lastReceivedData.messageType, lastReceivedData.data)
        );

        if (!success) {
            failedMessageDataGroup[lastReceivedMessageId] = lastReceivedData;
            revert BridgeRouterExecutedFailed(lastReceivedData.messageType, lastReceivedData.data);
        }
    }

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
