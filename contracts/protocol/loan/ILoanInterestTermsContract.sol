// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {Registry} from '../../storage/Registry.sol';
import '../../libraries/UnpackLoanParamtersLib.sol';

abstract contract ILoanInterestTermsContract {
    Registry public registry;

    mapping(bytes32 => bool) public startedLoan;

    mapping(bytes32 => uint256) public repaidPrincipalAmounts;
    mapping(bytes32 => uint256) public repaidInterestAmounts;

    mapping(bytes32 => bool) public completedRepayment;

    /// @notice register the start of a loan term
    function registerTermStart(bytes32 agreementId) public virtual returns (bool);

    /// @notice the total amount of principal and interest repaid for a given loan agreement
    function getValueRepaidToDate(bytes32 agreementId) public view virtual returns (uint256, uint256);

    /// @notice checks whether the repayments for a batch of loan agreements have been completed
    function isCompletedRepayments(bytes32[] memory agreementIds) public view virtual returns (bool[] memory);

    /// @dev set loan as repaid
    function registerConcludeLoan(bytes32 agreementId) external virtual returns (bool);

    uint256[46] private __gap;
}
