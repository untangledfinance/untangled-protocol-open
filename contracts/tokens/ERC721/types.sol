
// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

struct LoanAssetInfo {
    uint256 tokenId;
    uint256 nonce;
    address validator;
    bytes validateSignature;
}
