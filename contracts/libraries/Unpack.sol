// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

library Unpack {

    function unpackPrincipalAmount(bytes32 term) internal
    pure
    returns (uint) {
        return uint(term & 0x00ffffffffffffffffffffffff00000000000000000000000000000000000000) >> 152;
    }

    function unpackInterestRate(bytes32 term) internal
    pure
    returns (uint) {
        return uint(term & 0x00000000000000000000000000ffffff00000000000000000000000000000000) >> 128;
    }

    function unpackAmortizationUnitType(bytes32 term) internal
    pure
    returns (uint) {
        return uint(term & term & 0x00000000000000000000000000000000f0000000000000000000000000000000) >> 124;
    }

    function unpackTermLengthInAmortizationUnits(bytes32 term) internal
    pure
    returns (uint) {
        return uint(term & term & 0x000000000000000000000000000000000ffffffffffffffffffffffff0000000) >> 28;
    }

    function unpackGracePeriodInDays(bytes32 term) internal
    pure
    returns (uint gracePeriodInDays) {
        return uint(term & term & 0x000000000000000000000000000000000000000000000000000000000ff00000) >> 20;
    }
}
