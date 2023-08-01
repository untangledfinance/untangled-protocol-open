// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import './ISecuritizationPool.sol';

abstract contract IDistributionAssessor {
    function getSOTTokenPrice(address securitizationPool, uint256 timestamp) public view virtual returns (uint256);

    function getJOTTokenPrice(
        ISecuritizationPool securitizationPool,
        uint256 endTime
    ) public view virtual returns (uint256);

    function calcTokenPrice(address pool, address tokenAddress) external view virtual returns (uint256);

    function getCashBalance(address pool) public view virtual returns (uint256);

    function calcAssetValue(
        address pool,
        address tokenAddress,
        address investor
    ) external view virtual returns (uint256 principal, uint256 interest);

    function calcCorrespondingTotalAssetValue(
        address tokenAddress,
        address investor,
        uint256 timestamp
    ) external view virtual returns (uint256);
}
