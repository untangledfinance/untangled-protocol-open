// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import {MessageType} from '../ICommandData.sol';

interface IUntangledBridgeRouter {
    function processMessage(MessageType messageType, bytes calldata data) external;
}
