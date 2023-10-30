
// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

struct LoanAssetInfo {
    uint256[] tokenIds;
    uint256[] nonces;
    address validator;
    bytes validateSignature;
}

bytes32 constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");
bytes32 constant VALIDATOR_ADMIN_ROLE = keccak256("VALIDATOR_ADMIN_ROLE");