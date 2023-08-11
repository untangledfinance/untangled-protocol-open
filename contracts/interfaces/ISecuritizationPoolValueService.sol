// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISecuritizationPoolValueService {
    function getOutstandingPrincipalCurrencyByInvestor(address pool, address investor) external view returns (uint256);

    function getExpectedAssetsValue(address poolAddress, uint256 timestamp)
        external
        view
        returns (uint256 expectedAssetsValue);

    function getSeniorAsset(address poolAddress) external view returns (uint256);

    function getJuniorAsset(address poolAddress) external view returns (uint256);
}
