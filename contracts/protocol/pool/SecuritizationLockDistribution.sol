// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {PausableUpgradeable} from '../../base/PauseableUpgradeable.sol';
import {ERC165Upgradeable} from '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol';
import {ReentrancyGuardUpgradeable} from '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';

import {ISecuritizationLockDistribution} from './ISecuritizationLockDistribution.sol';
import {Registry} from '../../storage/Registry.sol';
import {ConfigHelper} from '../../libraries/ConfigHelper.sol';
import {RegistryInjection} from './RegistryInjection.sol';

import {ISecuritizationPoolExtension, SecuritizationPoolExtension} from './SecuritizationPoolExtension.sol';
import {SecuritizationAccessControl} from './SecuritizationAccessControl.sol';
import {SecuritizationPoolStorage} from './SecuritizationPoolStorage.sol';
import {ISecuritizationPoolStorage} from './ISecuritizationPoolStorage.sol';

// RegistryInjection,
// ERC165Upgradeable,
// PausableUpgradeable,
// SecuritizationPoolStorage,
// ISecuritizationLockDistribution

contract SecuritizationLockDistribution is
    ERC165Upgradeable,
    RegistryInjection,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    SecuritizationPoolExtension,
    SecuritizationPoolStorage,
    SecuritizationAccessControl,
    ISecuritizationLockDistribution
{
    using ConfigHelper for Registry;

    function installExtension(
        bytes memory params
    ) public virtual override(ISecuritizationPoolExtension, SecuritizationAccessControl, SecuritizationPoolStorage) onlyCallInTargetPool {}

    function lockedDistributeBalances(address tokenAddress, address investor) public view override returns (uint256) {
        Storage storage $ = _getStorage();
        return $.lockedDistributeBalances[tokenAddress][investor];
    }

    function lockedRedeemBalances(address tokenAddress, address investor) public view override returns (uint256) {
        Storage storage $ = _getStorage();
        return $.lockedRedeemBalances[tokenAddress][investor];
    }

    function totalLockedRedeemBalances(address tokenAddress) public view override returns (uint256) {
        Storage storage $ = _getStorage();
        return $.totalLockedRedeemBalances[tokenAddress];
    }

    function totalLockedDistributeBalance() public view override returns (uint256) {
        Storage storage $ = _getStorage();
        return $.totalLockedDistributeBalance;
    }

    function totalRedeemedCurrency() public view override returns (uint256) {
        Storage storage $ = _getStorage();
        return $.totalRedeemedCurrency;
    }

    // // token address -> user -> locked
    // mapping(address => mapping(address => uint256)) public override lockedDistributeBalances;

    // uint256 public override totalLockedDistributeBalance;

    // mapping(address => mapping(address => uint256)) public override lockedRedeemBalances;
    // // token address -> total locked
    // mapping(address => uint256) public override totalLockedRedeemBalances;

    // uint256 public override totalRedeemedCurrency; // Total $ (cUSD) has been redeemed

    // Increase by value
    function increaseLockedDistributeBalance(
        address tokenAddress,
        address investor,
        uint256 currency,
        uint256 token
    ) external override whenNotPaused {
        registry().requireDistributionOperator(_msgSender());

        Storage storage $ = _getStorage();

        $.lockedDistributeBalances[tokenAddress][investor] =
            $.lockedDistributeBalances[tokenAddress][investor] +
            currency;
        $.lockedRedeemBalances[tokenAddress][investor] = $.lockedRedeemBalances[tokenAddress][investor] + token;

        $.totalLockedDistributeBalance = $.totalLockedDistributeBalance + currency;
        $.totalLockedRedeemBalances[tokenAddress] = $.totalLockedRedeemBalances[tokenAddress] + token;

        emit UpdateLockedDistributeBalance(
            tokenAddress,
            investor,
            $.lockedDistributeBalances[tokenAddress][investor],
            $.lockedRedeemBalances[tokenAddress][investor],
            $.totalLockedRedeemBalances[tokenAddress],
            $.totalLockedDistributeBalance
        );

        emit UpdateTotalRedeemedCurrency($.totalRedeemedCurrency, tokenAddress);
        emit UpdateTotalLockedDistributeBalance($.totalLockedDistributeBalance, tokenAddress);
    }

    function decreaseLockedDistributeBalance(
        address tokenAddress,
        address investor,
        uint256 currency,
        uint256 token
    ) external override whenNotPaused {
        registry().requireDistributionOperator(_msgSender());

        Storage storage $ = _getStorage();

        $.lockedDistributeBalances[tokenAddress][investor] =
            $.lockedDistributeBalances[tokenAddress][investor] -
            currency;
        $.lockedRedeemBalances[tokenAddress][investor] = $.lockedRedeemBalances[tokenAddress][investor] - token;

        $.totalLockedDistributeBalance = $.totalLockedDistributeBalance - currency;
        $.totalRedeemedCurrency = $.totalRedeemedCurrency + currency;
        $.totalLockedRedeemBalances[tokenAddress] = $.totalLockedRedeemBalances[tokenAddress] - token;

        emit UpdateLockedDistributeBalance(
            tokenAddress,
            investor,
            $.lockedDistributeBalances[tokenAddress][investor],
            $.lockedRedeemBalances[tokenAddress][investor],
            $.totalLockedRedeemBalances[tokenAddress],
            $.totalLockedDistributeBalance
        );

        emit UpdateTotalRedeemedCurrency($.totalRedeemedCurrency, tokenAddress);
        emit UpdateTotalLockedDistributeBalance($.totalLockedDistributeBalance, tokenAddress);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(ERC165Upgradeable, SecuritizationAccessControl, SecuritizationPoolStorage)
        returns (bool)
    {
        return super.supportsInterface(interfaceId) || type(ISecuritizationLockDistribution).interfaceId == interfaceId;
    }

    function pause() public virtual {
        registry().requirePoolAdminOrOwner(address(this), _msgSender());
        _pause();
    }

    function unpause() public virtual {
        registry().requirePoolAdminOrOwner(address(this), _msgSender());
        _unpause();
    }

    function getFunctionSignatures()
        public
        view
        virtual
        override(ISecuritizationPoolExtension, SecuritizationAccessControl, SecuritizationPoolStorage)
        returns (bytes4[] memory)
    {
        bytes4[] memory _functionSignatures = new bytes4[](8);

        _functionSignatures[0] = this.totalRedeemedCurrency.selector;
        _functionSignatures[1] = this.lockedDistributeBalances.selector;
        _functionSignatures[2] = this.lockedRedeemBalances.selector;
        _functionSignatures[3] = this.totalLockedRedeemBalances.selector;
        _functionSignatures[4] = this.totalLockedDistributeBalance.selector;
        _functionSignatures[5] = this.increaseLockedDistributeBalance.selector;
        _functionSignatures[6] = this.decreaseLockedDistributeBalance.selector;
        _functionSignatures[7] = this.supportsInterface.selector;

        return _functionSignatures;
    }
}
