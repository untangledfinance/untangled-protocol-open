// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

enum MessageType {
    LenderBuysTokens
}

struct ICommandData {
    MessageType messageType;
    bytes data;
}
