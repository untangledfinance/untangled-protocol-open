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

    function lockedDistributeBalances(address tokenAddress, address investor) external view returns (uint256);

    function lockedRedeemBalances(address tokenAddress, address investor) external view returns (uint256);

    function totalLockedRedeemBalances(address tokenAddress) external view returns (uint256);

    function totalLockedDistributeBalance() external view returns (uint256);

    function increaseLockedDistributeBalance(
        address tokenAddress,
        address investor,
        uint256 currency,
        uint256 token
    ) external;
}
