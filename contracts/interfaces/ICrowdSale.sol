// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

abstract contract ICrowdSale {
    mapping(address => uint256) public currencyRaisedByInvestor;

    uint256 public currencyRaised;
}
