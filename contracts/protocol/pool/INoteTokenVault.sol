// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

interface INoteTokenVault {
    event RedeemSOTOrder(address pool, address usr, uint256 newRedeemAmount);
    event RedeemJOTOrder(address pool, address usr, uint256 newRedeemAmount);
    event DisburseSOTOrder(address pool, address[] toAddresses, uint256[] amounts, uint256[] redeemedAmount);
    event SetRedeemDisabled(address pool, bool _redeemDisabled);

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

    function disburseAllForSOT(address pool, address[] memory toAddresses, uint256[] memory amounts, uint256[] memory redeemedAmount) external;

//    function disburseAllForJOT(address pool, address[] memory toAddresses, uint256[] memory amounts, uint256[] memory redeemedAmount) external;

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
