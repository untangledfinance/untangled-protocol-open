// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '../../../base/UntangledBase.sol';
import {MessageType} from '../ICommandData.sol';
import {IUntangledBridgeRouter} from '../interfaces/IUntangledBridgeRouter.sol';

contract UntangledBridgeRouterV2 is UntangledBase, IUntangledBridgeRouter {
    bytes32 public constant CCIP_RECEIVER_ROLE = keccak256('CCIP_RECEIVER_ROLE');

    function initialize(address owner) public initializer {
        __UntangledBase__init_unchained(_msgSender());
        _setupRole(CCIP_RECEIVER_ROLE, owner);
    }

    function processMessage(MessageType messageType, bytes calldata data) external onlyRole(CCIP_RECEIVER_ROLE) {}

    function hello() public pure returns (string memory greeting) {
        return 'Hello world';
    }
}
