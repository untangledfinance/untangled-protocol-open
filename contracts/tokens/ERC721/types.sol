
// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

struct LoanAssetInfo {
    uint256 tokenId;
    uint256 nonce;
    address validator;
    bytes validateSignature;
}

bytes32 constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");
bytes32 constant VALIDATOR_ADMIN_ROLE = keccak256("VALIDATOR_ADMIN_ROLE");