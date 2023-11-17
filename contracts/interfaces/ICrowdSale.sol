// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface ICrowdSale {
    function currencyRaisedByInvestor(address investor) external view returns (uint256);

    function currencyRaised() external view returns (uint256);

    function firstNoteTokenMintedTimestamp() external view returns (uint64);

    function buyTokens(address payee, address beneficiary, uint256 currencyAmount) external returns (uint256);
}
