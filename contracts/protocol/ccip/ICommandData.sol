// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

enum MessageType {
    LenderBuysTokens
}

struct ICommandData {
    MessageType messageType;
    bytes data;
}
