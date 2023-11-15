// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ISecuritizationLockDistribution {
    event UpdateLockedDistributeBalance(
        address indexed tokenAddress,
        address indexed investor,
        uint256 lockedDistributeBalance,
        uint256 lockedRedeemBalances,
        uint256 totalLockedRedeemBalances,
        uint256 totalLockedDistributeBalance
    );

    // Total $ (cUSD) has been redeemed
    function totalRedeemedCurrency() external view returns (uint256);

    // token address -> user -> locked
    function lockedDistributeBalances(address tokenAddress, address investor) external view returns (uint256);

    // token address -> total locked
    function lockedRedeemBalances(address tokenAddress, address investor) external view returns (uint256);

    // token address -> total locked
    function totalLockedRedeemBalances(address tokenAddress) external view returns (uint256);

    // for lending operation
    function totalLockedDistributeBalance() external view returns (uint256);

    /// @notice increases the locked distribution balance for a specific investor
    function increaseLockedDistributeBalance(
        address tokenAddress,
        address investor,
        uint256 currency,
        uint256 token
    ) external;

    /// @notice decreases the locked distribution balance for a specific investor
    function decreaseLockedDistributeBalance(
        address tokenAddress,
        address investor,
        uint256 currency,
        uint256 token
    ) external;

    /// @notice allows the redemption of tokens
    function redeem(address usr, address notesToken, uint256 currencyAmount, uint256 tokenAmount) external;
}
