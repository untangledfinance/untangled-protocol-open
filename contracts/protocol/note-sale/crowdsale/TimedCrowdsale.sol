// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './Crowdsale.sol';

contract TimedCrowdsale is Crowdsale {
    uint256 public openingTime;
    uint256 public closingTime;

    bool public isEnableTimeLimit;

    event TimedCrowdsaleExtended(uint256 prevClosingTime, uint256 newClosingTime);

    function __TimedCrowdsale__init() internal onlyInitializing {
        __Crowdsale__init();

        isEnableTimeLimit = true;
    }

    modifier onlyWhileOpen() {
        require(isOpen() || isLongSale(), 'TimedCrowdsale: not open');
        _;
    }

    function isOpen() public view returns (bool) {
        if (!isEnableTimeLimit) {
            return true;
        }
        // solhint-disable-next-line not-rely-on-time
        return block.timestamp >= openingTime && block.timestamp <= closingTime;
    }

    function hasClosed() public view returns (bool) {
        // solhint-disable-next-line not-rely-on-time
        return block.timestamp > closingTime;
    }

    function extendTime(uint256 newClosingTime) external whenNotPaused nonReentrant onlyRole(OWNER_ROLE) {
        require(newClosingTime > closingTime, 'TimedCrowdsale: new closing time is before current closing time');

        emit TimedCrowdsaleExtended(closingTime, newClosingTime);
        closingTime = newClosingTime;
    }

    function newSaleRoundTime(uint256 newOpeningTime, uint256 newClosingTime) public whenNotPaused onlyRole(OWNER_ROLE) {
        require(newClosingTime >= newOpeningTime, 'TimedCrowdsale: opening time is not before closing time');
        // not accept opening time in the past
        if (newOpeningTime < block.timestamp) {
            newOpeningTime = block.timestamp;
        }

        if (newClosingTime <= newOpeningTime) {
            newClosingTime = newOpeningTime + 1;
        }

        openingTime = newOpeningTime;
        closingTime = newClosingTime;
    }

    function setUsingTimeLimit(bool usingTimeLimit) public whenNotPaused nonReentrant onlyRole(OWNER_ROLE) {
        isEnableTimeLimit = usingTimeLimit;
    }
}
