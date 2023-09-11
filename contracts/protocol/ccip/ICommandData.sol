// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

enum MessageType {
    LenderBuysTokens
}

struct ICommandData {
    MessageType messageType;
    bytes data;
}
