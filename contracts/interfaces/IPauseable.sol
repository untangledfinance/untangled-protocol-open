// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

interface IPauseable {
    function pause() external;
    function unpause() external;
}
