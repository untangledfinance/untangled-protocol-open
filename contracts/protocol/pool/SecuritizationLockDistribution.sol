// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {PausableUpgradeable} from '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import {ISecuritizationLockDistribution} from './ISecuritizationLockDistribution.sol';
import {Registry} from '../../storage/Registry.sol';
import {ConfigHelper} from '../../libraries/ConfigHelper.sol';
import {RegistryInjection} from './RegistryInjection.sol';

abstract contract SecuritizationLockDistribution is
    PausableUpgradeable,
    RegistryInjection,
    ISecuritizationLockDistribution
{
    using ConfigHelper for Registry;

    // keccak256(abi.encode(uint256(keccak256("untangled.storage.SecuritizationLockDistribution")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant SecuritizationLockDistributionStorageLocation =
        0xaa8b848cd9e2a85edbb7908b73c85a1343a78bc77e13720d307e4378313e0500;

    /// @custom:storage-location erc7201:untangled.storage.SecuritizationLockDistribution
    struct SecuritizationLockDistributionStorage {
        mapping(address => mapping(address => uint256)) lockedDistributeBalances;
        uint256 totalLockedDistributeBalance;
        mapping(address => mapping(address => uint256)) lockedRedeemBalances;
        // token address -> total locked
        mapping(address => uint256) totalLockedRedeemBalances;
        uint256 totalRedeemedCurrency; // Total $ (cUSD) has been redeemed
    }

    function _getSecuritizationLockDistributionStorage()
        private
        pure
        returns (SecuritizationLockDistributionStorage storage $)
    {
        assembly {
            $.slot := SecuritizationLockDistributionStorageLocation
        }
    }

    function lockedDistributeBalances(address tokenAddress, address investor) public view override returns (uint256) {
        SecuritizationLockDistributionStorage storage $ = _getSecuritizationLockDistributionStorage();
        return $.lockedDistributeBalances[tokenAddress][investor];
    }

    function lockedRedeemBalances(address tokenAddress, address investor) public view override returns (uint256) {
        SecuritizationLockDistributionStorage storage $ = _getSecuritizationLockDistributionStorage();
        return $.lockedRedeemBalances[tokenAddress][investor];
    }

    function totalLockedRedeemBalances(address tokenAddress) public view override returns (uint256) {
        SecuritizationLockDistributionStorage storage $ = _getSecuritizationLockDistributionStorage();
        return $.totalLockedRedeemBalances[tokenAddress];
    }

    function totalLockedDistributeBalance() public view override returns (uint256) {
        SecuritizationLockDistributionStorage storage $ = _getSecuritizationLockDistributionStorage();
        return $.totalLockedDistributeBalance;
    }

    function totalRedeemedCurrency() public view override returns (uint256) {
        SecuritizationLockDistributionStorage storage $ = _getSecuritizationLockDistributionStorage();
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

        SecuritizationLockDistributionStorage storage $ = _getSecuritizationLockDistributionStorage();

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

        SecuritizationLockDistributionStorage storage $ = _getSecuritizationLockDistributionStorage();

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
}
