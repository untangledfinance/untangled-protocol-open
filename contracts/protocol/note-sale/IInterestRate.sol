// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IInterestRate {
    function pickedInterest() external view returns (uint32);
}
