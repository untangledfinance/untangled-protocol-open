// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IDistributionTranche {
    /// @notice allows the redemption of tokens for a specific redeemer from a specified pool and tokenAddress
    function redeem(
        address usr,
        address pool,
        address notesToken,
        uint256 currencyAmount,
        uint256 tokenAmount
    ) external;

    /// @notice allows the distribution operator to redeem tokenAmount tokens of a specific noteToken from a given usr
    function redeemToken(
        address noteToken,
        address usr,
        uint256 tokenAmount
    ) external;
}
