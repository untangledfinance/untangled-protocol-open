// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import '../storage/Registry.sol';

abstract contract ILoanInterestTermsContract {
    Registry public registry;

    mapping(bytes32 => bool) public startedLoan;

    mapping(bytes32 => uint256) public repaidPrincipalAmounts;
    mapping(bytes32 => uint256) public repaidInterestAmounts;

    mapping(bytes32 => bool) public completedRepayment;

    // Register to start Loan term for batch of agreement Ids
    function registerTermStart(bytes32 agreementId) public virtual returns (bool);

    function getValueRepaidToDate(bytes32 agreementId) public view virtual returns (uint256, uint256);

    function isCompletedRepayments(bytes32[] memory agreementIds) public view virtual returns (bool[] memory);

    /**
     * Expected repayment value with Amortization of Interest and Principal
     * (AMORTIZATION) - will be used for repayment from Debtor
     */
    function getExpectedRepaymentValues(bytes32 agreementId, uint256 timestamp)
        public
        view
        virtual
        returns (uint256 expectedPrincipal, uint256 expectedInterest);

    function getMultiExpectedRepaymentValues(bytes32[] memory agreementIds, uint256 timestamp)
        public
        view
        virtual
        returns (uint256[] memory, uint256[] memory);

    function registerConcludeLoan(bytes32 agreementId) external virtual returns (bool);

    /// When called, the registerRepayment function records the debtor's
    ///  repayment, as well as any auxiliary metadata needed by the contract
    ///  to determine ex post facto the value repaid (e.g. current USD
    ///  exchange rate)
    /// @param  agreementId bytes32. The agreement id (issuance hash) of the debt agreement to which this pertains.
    /// @param  payer address. The address of the payer.
    /// @param  beneficiary address. The address of the payment's beneficiary.
    /// @param  unitsOfRepayment uint. The units-of-value repaid in the transaction.
    /// @param  tokenAddress address. The address of the token with which the repayment transaction was executed.
    function registerRepayment(
        bytes32 agreementId,
        address payer,
        address beneficiary,
        uint256 unitsOfRepayment,
        address tokenAddress
    ) public virtual returns (uint256 remains);

    function getInterestRate(bytes32 agreementId) public view virtual returns (uint256);
}
