// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ICrowdSale {
    function currencyRaisedByInvestor(address investor) external view returns (uint256);

    function currencyRaised() external view returns (uint256);

    function buyTokens(address payee, address beneficiary, uint256 currencyAmount) external returns (uint256);
}
