// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {PausableUpgradeable} from '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import {ISecuritizationLockDistribution} from './ISecuritizationLockDistribution.sol';
import {Registry} from '../../storage/Registry.sol';
import {ConfigHelper} from '../../libraries/ConfigHelper.sol';

contract SecuritizationLockDistribution is PausableUpgradeable, ISecuritizationLockDistribution {
    using ConfigHelper for Registry;

    Registry public registry;

    // token address -> user -> locked
    mapping(address => mapping(address => uint256)) public lockedDistributeBalances;
    uint256 public totalLockedDistributeBalance;

    mapping(address => mapping(address => uint256)) public lockedRedeemBalances;
    // token address -> total locked
    mapping(address => uint256) public totalLockedRedeemBalances;

    // Increase by value
    function increaseLockedDistributeBalance(
        address tokenAddress,
        address investor,
        uint256 currency,
        uint256 token
    ) external override whenNotPaused {
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
}
