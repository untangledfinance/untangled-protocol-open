// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.19;

import {MessageType} from '../ICommandData.sol';

interface IUntangledBridgeRouter {
    function processMessage(MessageType messageType, bytes calldata data) external;
}
