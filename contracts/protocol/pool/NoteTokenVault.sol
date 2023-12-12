// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';

import {INoteTokenVault} from "./INoteTokenVault.sol";
import {INoteToken} from '../../interfaces/INoteToken.sol';
import {ISecuritizationTGE} from './ISecuritizationTGE.sol';

/// @title NoteTokenVault
/// @author Untangled Team
/// @notice NoteToken redemption
contract NoteTokenVault is Initializable, PausableUpgradeable, INoteTokenVault {

    /// @dev Pool redeem disabled value
    mapping(address => bool) public poolRedeemDisabled;
    /// @dev Pool total SOT redeem
    mapping(address => uint256) public poolTotalSOTRedeem;
    /// @dev Pool total JOT redeem
    mapping(address => uint256) public poolTotalJOTRedeem;
    /// @dev Pool user redeem order
    mapping(address => mapping(address => UserOrder)) public poolUserRedeems;

    modifier orderAllowed(address pool) {
        require(
            poolRedeemDisabled[pool] == false,
            "redeem-not-allowed"
        );
        _;
    }

    function initialize() public initializer {
        __Pausable_init_unchained();
    }

    /// @inheritdoc INoteTokenVault
    function redeemJOTOrder(address pool, uint256 newRedeemAmount) public orderAllowed(pool) {
        address usr = _msgSender();
        uint256 currentRedeemAmount = poolUserRedeems[pool][usr].redeemJOTAmount;
        poolUserRedeems[pool][usr].redeemJOTAmount = newRedeemAmount;
        poolTotalJOTRedeem[pool] = poolTotalJOTRedeem[pool] - currentRedeemAmount + newRedeemAmount;

        uint256 delta;
        if (newRedeemAmount > currentRedeemAmount) {
            delta = newRedeemAmount - currentRedeemAmount;
            require(INoteToken(ISecuritizationTGE(pool).jotToken()).transferFrom(usr, address(this), delta), "token-transfer-to-pool-failed");
            return;
        }

        delta = currentRedeemAmount - newRedeemAmount;
        if (delta > 0) {
            require(INoteToken(ISecuritizationTGE(pool).jotToken()).transfer(usr, delta), "token-transfer-out-failed");
        }

        emit RedeemJOTOrder(pool, usr, newRedeemAmount);
    }

    /// @inheritdoc INoteTokenVault
    function redeemSOTOrder(address pool, uint256 newRedeemAmount) public orderAllowed(pool) {
        address usr = _msgSender();
        uint256 currentRedeemAmount = poolUserRedeems[pool][usr].redeemSOTAmount;
        poolUserRedeems[pool][usr].redeemSOTAmount = newRedeemAmount;
        poolTotalSOTRedeem[pool] = poolTotalSOTRedeem[pool] - currentRedeemAmount + newRedeemAmount;

        uint256 delta;
        if (newRedeemAmount > currentRedeemAmount) {
            delta = newRedeemAmount - currentRedeemAmount;
            require(INoteToken(ISecuritizationTGE(pool).sotToken()).transferFrom(usr, address(this), delta), "token-transfer-to-pool-failed");
            return;
        }

        delta = currentRedeemAmount - newRedeemAmount;
        if (delta > 0) {
            require(INoteToken(ISecuritizationTGE(pool).sotToken()).transfer(usr, delta), "token-transfer-out-failed");
        }

        emit RedeemSOTOrder(pool, usr, newRedeemAmount);
    }

    uint256[49] private __gap;
}
