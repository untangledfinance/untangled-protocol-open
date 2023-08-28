// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IDistributionTranche {
    function redeem(
        address usr,
        address pool,
        address notesToken,
        uint256 currencyAmount,
        uint256 tokenAmount
    ) external;

    function redeemToken(
        address noteToken,
        address usr,
        uint256 tokenAmount
    ) external returns (bool);
}
