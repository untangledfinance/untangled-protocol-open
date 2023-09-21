// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

interface IPauseable {
    function pause() external;
    function unpause() external;
}
