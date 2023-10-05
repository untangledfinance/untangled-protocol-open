// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ISecuritizationPoolValueService {
    /// @notice calculates the outstanding principal in currency amount for a given investor address.
    /// It takes the investor address as a parameter and returns the outstanding principal
    function getOutstandingPrincipalCurrencyByInvestor(address pool, address investor) external view returns (uint256);

    /// @notice calculates the total expected value of all assets in the securitization pool at a given timestamp
    /// @dev iterates over the NFT assets and token assets in the pool, calling getExpectedAssetValue
    /// or getExpectedERC20AssetValue for each asset and summing up the values
    function getExpectedAssetsValue(address poolAddress, uint256 timestamp)
        external
        view
        returns (uint256 expectedAssetsValue);

    /// @notice the amount which belongs to the senior investor (SOT) in a pool
    /// @dev  calculates  the amount which accrues interest for the senior tranche in the securitization pool at a given timestamp
    function getSeniorAsset(address poolAddress) external view returns (uint256);

    /// @notice calculates  the amount of Junior Debt at the current time
    function getJuniorAsset(address poolAddress) external view returns (uint256);

    /// @notice returns the rate that belongs to Junior investors at the current time
    function getJuniorRatio(address poolAddress) external view returns (uint256);

    /// @notice calculates the expected value of an asset in the securitization pool at a given timestamp
    function getExpectedAssetValue(
        address poolAddress,
        address tokenAddress,
        uint256 tokenId,
        uint256 timestamp
    ) external view returns (uint256);

    /// @notice calculates the expected value of an ERC20 asset in the securitization pool at a given timestamp
    function getExpectedERC20AssetValue(
        address poolAddress,
        address assetPoolAddress,
        address tokenAddress,
        uint256 interestRate,
        uint256 timestamp
    ) external view returns (uint256);
}
