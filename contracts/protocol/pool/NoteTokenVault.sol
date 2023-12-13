// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol';
import {ERC20BurnableUpgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol';
import {IERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol';

import {UntangledMath} from '../../libraries/UntangledMath.sol';
import {INoteTokenVault} from "./INoteTokenVault.sol";
import {INoteToken} from '../../interfaces/INoteToken.sol';
import {ISecuritizationTGE} from './ISecuritizationTGE.sol';
import { BACKEND_ADMIN } from './types.sol';

/// @title NoteTokenVault
/// @author Untangled Team
/// @notice NoteToken redemption
contract NoteTokenVault is Initializable, PausableUpgradeable, AccessControlEnumerableUpgradeable, INoteTokenVault {
    /// @dev Pool redeem disabled value
    mapping(address => bool) public poolRedeemDisabled;
    /// @dev Pool total SOT redeem
    mapping(address => uint256) public poolTotalSOTRedeem;
    /// @dev Pool total JOT redeem
    mapping(address => uint256) public poolTotalJOTRedeem;
    /// @dev Pool user redeem order
    mapping(address => mapping(address => UserOrder)) public poolUserRedeems;

    /// @dev Checks if redeeming is allowed for a given pool.
    /// @param pool The address of the pool to check.
    modifier orderAllowed(address pool) {
        require(
            poolRedeemDisabled[pool] == false,
            "redeem-not-allowed"
        );
        _;
    }

    function initialize() public initializer {
        __Pausable_init_unchained();
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
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

    /// @inheritdoc INoteTokenVault
    function disburseAllForSOT(
        address pool,
        address[] memory toAddresses,
        uint256[] memory amounts,
        uint256[] memory redeemedAmounts
    ) onlyRole(BACKEND_ADMIN) public {
        ISecuritizationTGE poolTGE = ISecuritizationTGE(pool);
        uint256 userLength = toAddresses.length;
        uint256 totalAmount = 0;
        uint256 totalSOTRedeemed = 0;

        for (uint256 i = 0; i < userLength; i = UntangledMath.uncheckedInc(i)) {
            totalAmount += amounts[i];
            totalSOTRedeemed += redeemedAmounts[i];
            poolTGE.disburse(toAddresses[i], amounts[i]);
            poolUserRedeems[pool][toAddresses[i]].redeemSOTAmount -= redeemedAmounts[i];
            ERC20BurnableUpgradeable(poolTGE.sotToken()).burn(redeemedAmounts[i]);
        }

        poolTotalSOTRedeem[pool] -= totalSOTRedeemed;
        poolTGE.decreaseReserve(totalAmount);
        emit DisburseSOTOrder(pool, toAddresses, amounts, redeemedAmounts);
    }

    /// @inheritdoc INoteTokenVault
    function disburseAllForJOT(
        address pool,
        address[] memory toAddresses,
        uint256[] memory amounts,
        uint256[] memory redeemedAmounts
    ) onlyRole(BACKEND_ADMIN) public {
        ISecuritizationTGE poolTGE = ISecuritizationTGE(pool);
        uint256 userLength = toAddresses.length;
        uint256 totalAmount = 0;
        uint256 totalJOTRedeemed = 0;

        for (uint256 i = 0; i < userLength; i = UntangledMath.uncheckedInc(i)) {
            totalAmount += amounts[i];
            totalJOTRedeemed += redeemedAmounts[i];
            poolTGE.disburse(toAddresses[i], amounts[i]);
            poolUserRedeems[pool][toAddresses[i]].redeemJOTAmount -= redeemedAmounts[i];
            ERC20BurnableUpgradeable(poolTGE.jotToken()).burn(redeemedAmounts[i]);
        }

        poolTotalJOTRedeem[pool] -= totalJOTRedeemed;
        poolTGE.decreaseReserve(totalAmount);
        emit DisburseJOTOrder(pool, toAddresses, amounts, redeemedAmounts);
    }

    /// @inheritdoc INoteTokenVault
    function setRedeemDisabled(address pool, bool _redeemDisabled) onlyRole(BACKEND_ADMIN) public {
        poolRedeemDisabled[pool] = _redeemDisabled;
        emit SetRedeemDisabled(pool, _redeemDisabled);
    }

    /// @inheritdoc INoteTokenVault
    function redeemDisabled(address pool) public view returns (bool) {
        return poolRedeemDisabled[pool];
    }

    /// @inheritdoc INoteTokenVault
    function totalJOTRedeem(address pool) public view override returns (uint256) {
        return poolTotalJOTRedeem[pool];
    }

    /// @inheritdoc INoteTokenVault
    function totalSOTRedeem(address pool) public view override returns (uint256) {
        return poolTotalSOTRedeem[pool];
    }

    /// @inheritdoc INoteTokenVault
    function userRedeemJOTOrder(address pool, address usr) public view override returns (uint256) {
        return poolUserRedeems[pool][usr].redeemJOTAmount;
    }

    /// @inheritdoc INoteTokenVault
    function userRedeemSOTOrder(address pool, address usr) public view override returns (uint256) {
        return poolUserRedeems[pool][usr].redeemSOTAmount;
    }

    uint256[49] private __gap;
}
