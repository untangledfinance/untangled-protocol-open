// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {PausableUpgradeable} from '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import {ISecuritizationLockDistribution} from './ISecuritizationLockDistribution.sol';
import {Registry} from '../../storage/Registry.sol';
import {ConfigHelper} from '../../libraries/ConfigHelper.sol';

abstract contract SecuritizationLockDistribution is PausableUpgradeable, ISecuritizationLockDistribution {
    using ConfigHelper for Registry;

    Registry public registry;

    // token address -> user -> locked
    mapping(address => mapping(address => uint256)) public override lockedDistributeBalances;
    uint256 public override totalLockedDistributeBalance;

    mapping(address => mapping(address => uint256)) public override lockedRedeemBalances;
    // token address -> total locked
    mapping(address => uint256) public override totalLockedRedeemBalances;

    uint256 public override totalRedeemedCurrency; // Total $ (cUSD) has been redeemed

    // Increase by value
    function increaseLockedDistributeBalance(
        address tokenAddress,
        address investor,
        uint256 currency,
        uint256 token
    ) external override whenNotPaused {
        registry.requireDistributionOperator(_msgSender());

        lockedDistributeBalances[tokenAddress][investor] = lockedDistributeBalances[tokenAddress][investor] + currency;
        lockedRedeemBalances[tokenAddress][investor] = lockedRedeemBalances[tokenAddress][investor] + token;

        totalLockedDistributeBalance = totalLockedDistributeBalance + currency;
        totalLockedRedeemBalances[tokenAddress] = totalLockedRedeemBalances[tokenAddress] + token;

        emit UpdateLockedDistributeBalance(
            tokenAddress,
            investor,
            lockedDistributeBalances[tokenAddress][investor],
            lockedRedeemBalances[tokenAddress][investor],
            totalLockedRedeemBalances[tokenAddress],
            totalLockedDistributeBalance
        );
    }

    function decreaseLockedDistributeBalance(
        address tokenAddress,
        address investor,
        uint256 currency,
        uint256 token
    ) external override whenNotPaused {
        registry.requireDistributionOperator(_msgSender());

        lockedDistributeBalances[tokenAddress][investor] = lockedDistributeBalances[tokenAddress][investor] - currency;
        lockedRedeemBalances[tokenAddress][investor] = lockedRedeemBalances[tokenAddress][investor] - token;

        totalLockedDistributeBalance = totalLockedDistributeBalance - currency;
        totalRedeemedCurrency = totalRedeemedCurrency + currency;
        totalLockedRedeemBalances[tokenAddress] = totalLockedRedeemBalances[tokenAddress] - token;

        emit UpdateLockedDistributeBalance(
            tokenAddress,
            investor,
            lockedDistributeBalances[tokenAddress][investor],
            lockedRedeemBalances[tokenAddress][investor],
            totalLockedRedeemBalances[tokenAddress],
            totalLockedDistributeBalance
        );
    }
}
