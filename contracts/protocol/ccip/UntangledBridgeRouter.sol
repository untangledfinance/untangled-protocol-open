// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import 'hardhat/console.sol';

import '../../base/UntangledBase.sol';
import {MessageType} from './ICommandData.sol';
import {IUntangledBridgeRouter} from './interfaces/IUntangledBridgeRouter.sol';

contract UntangledBridgeRouter is UntangledBase, IUntangledBridgeRouter {
    bytes32 public constant CCIP_RECEIVER_ROLE = keccak256('CCIP_RECEIVER_ROLE');

    function initialize(address owner) public initializer {
        __UntangledBase__init_unchained(_msgSender());
        _setupRole(CCIP_RECEIVER_ROLE, owner);
    }

    function processMessage(MessageType messageType, bytes calldata data) external onlyRole(CCIP_RECEIVER_ROLE) {
        console.log(uint8(messageType));
        console.logBytes(data);
    }
}
