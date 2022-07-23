// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

library Unpack16 {

    function unpackCollateralTokenId(bytes16 collateralParams) internal
    pure
    returns (uint) {
        return uint(uint128(collateralParams) & 0xffffffff000000000000000000000000) >> 96;
    }

    function unpackCollateralAmount(bytes16 collateralParams) internal
    pure
    returns (uint) {
        return uint(uint128(collateralParams) & 0x00000000ffffffffffffffffffffffff);
    }
}
