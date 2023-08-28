// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./ISecuritizationPool.sol";

abstract contract IDistributionAssessor {
    function getSOTTokenPrice(address securitizationPool) public view virtual returns (uint256);

    function getJOTTokenPrice(ISecuritizationPool securitizationPool) public view virtual returns (uint256);

    function calcTokenPrice(address pool, address tokenAddress) external view virtual returns (uint256);

    function getCashBalance(address pool) public view virtual returns (uint256);

    function calcCorrespondingTotalAssetValue(
        address tokenAddress,
        address investor
    ) external view virtual returns (uint256);
}
