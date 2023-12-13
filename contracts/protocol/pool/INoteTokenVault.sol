// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface INoteTokenVault {
    event RedeemSOTOrder(address pool, address usr, uint256 newRedeemAmount);
    event RedeemJOTOrder(address pool, address usr, uint256 newRedeemAmount);
    event DisburseSOTOrder(address pool, address[] toAddresses, uint256[] amounts, uint256[] redeemedAmount);
    event DisburseJOTOrder(address pool, address[] toAddresses, uint256[] amounts, uint256[] redeemedAmount);
    event SetRedeemDisabled(address pool, bool _redeemDisabled);

    /// @title UserOrder
    /// @dev Represents a user's order containing the amount of SOT and JOT to redeem.
    struct UserOrder {
        uint256 redeemSOTAmount;
        uint256 redeemJOTAmount;
    }

    /// @notice redeemJOTOrder function can be used to place or revoke a redeem
    /// @param newRedeemAmount new amount of tokens to be redeemed
    function redeemJOTOrder(address pool, uint256 newRedeemAmount) external;

    /// @notice redeemSOTOrder function can be used to place or revoke a redeem
    /// @param newRedeemAmount new amount of tokens to be redeemed
    function redeemSOTOrder(address pool, uint256 newRedeemAmount) external;

    /// @dev Disburses funds and handles SOT redemptions for a pool.
    /// @param pool The address of the pool contract.
    /// @param toAddresses An array of recipient addresses.
    /// @param amounts An array of amounts to disburse to each recipient.
    /// @param redeemedAmounts An array of SOT amounts redeemed by each recipient.
    /// @notice Only accessible by BACKEND_ADMIN role.
    function disburseAllForSOT(address pool, address[] memory toAddresses, uint256[] memory amounts, uint256[] memory redeemedAmounts) external;

    /// @dev Disburses funds and handles JOT redemptions for a pool.
    /// @param pool The address of the pool contract.
    /// @param toAddresses An array of recipient addresses.
    /// @param amounts An array of amounts to disburse to each recipient.
    /// @param redeemedAmounts An array of JOT amounts redeemed by each recipient.
    /// @notice Only accessible by BACKEND_ADMIN role.
    function disburseAllForJOT(address pool, address[] memory toAddresses, uint256[] memory amounts, uint256[] memory redeemedAmounts) external;

    /// @notice Pause redeem request
    function setRedeemDisabled(address pool, bool _redeemDisabled) external;

    /// @notice Total amount of SOT redeem order
    function totalSOTRedeem(address pool) external view returns (uint256);

    /// @notice Get redeem disabled
    function redeemDisabled(address pool) external view returns (bool);

    /// @notice Total amount of JOT redeem order
    function totalJOTRedeem(address pool) external view returns (uint256);

    /// @dev Retrieves the amount of JOT tokens that can be redeemed for the specified user.
    /// @param usr The address of the user for which to retrieve the redeemable JOT amount.
    /// @return The amount of JOT tokens that can be redeemed by the user.
    function userRedeemJOTOrder(address pool, address usr) external view returns (uint256);
    function userRedeemSOTOrder(address pool, address usr) external view returns (uint256);
}
