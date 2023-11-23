// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

bytes32 constant OWNER_ROLE = keccak256('OWNER_ROLE');
bytes32 constant POOL_ADMIN = keccak256('POOL_CREATOR');
bytes32 constant ORIGINATOR_ROLE = keccak256('ORIGINATOR_ROLE');

uint256 constant RATE_SCALING_FACTOR = 10 ** 4;