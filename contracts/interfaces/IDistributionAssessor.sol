// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;
import "./ISecuritizationPool.sol";

abstract contract IDistributionAssessor {
    /// @notice current individual asset price for the "SOT" tranche at the current timestamp
    function getSOTTokenPrice(address securitizationPool) public view virtual returns (uint256);

    /// @notice calculates the token price for the "JOT" tranche at the current timestamp
    function getJOTTokenPrice(ISecuritizationPool securitizationPool) public view virtual returns (uint256);

    /// @notice calculates the token price for a specific token address in the securitization pool
    function calcTokenPrice(address pool, address tokenAddress) external view virtual returns (uint256);

    /// @notice the available cash balance in the securitization pool
    function getCashBalance(address pool) public view virtual returns (uint256);

    /// @notice calculates the corresponding total asset value for a specific token address, investor, and end time
    function calcCorrespondingTotalAssetValue(
        address tokenAddress,
        address investor
    ) external view virtual returns (uint256);
}
