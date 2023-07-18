// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './Registry.sol';

abstract contract ILoanRegistry {
    Registry public registry;

    // loan -> debtors
    struct LoanEntry {
        address loanTermContract;
        address debtor;
        address principalTokenAddress;
        bytes32 termsParam; // actually inside this param was already included P token address
        uint256 salt;
        uint256 issuanceBlockTimestamp;
        uint256 lastRepayTimestamp;
        uint256 expirationTimestamp;
        uint8 riskScore;
        Configuration.ASSET_PURPOSE assetPurpose;
    }

    mapping(bytes32 => LoanEntry) public entries;

    mapping(bytes32 => bool) public manualInterestLoan;
    mapping(bytes32 => uint256) public manualInterestAmountLoan;

    mapping(bytes32 => bool) public completedLoans;

    function initialize(Registry _registry) public virtual;

    /**
     * Record new External Loan to blockchain
     */
    function insert(
        bytes32 tokenId,
        address termContract,
        address debtor,
        bytes32 termsContractParameter,
        address pTokenAddress,
        uint256 _salt,
        uint256 expirationTimestampInSecs,
        uint8[] calldata assetPurposeAndRiskScore
    ) external virtual returns (bool);

    function getLoanDebtor(bytes32 tokenId) public view virtual returns (address);

    function getLoanTermParams(bytes32 tokenId) public view virtual returns (bytes32);

    function getPrincipalTokenAddress(bytes32 agreementId) public view virtual returns (address);

    function getDebtor(bytes32 agreementId) public view virtual returns (address);

    function getTermContract(bytes32 agreementId) public view virtual returns (address);

    function getRiskScore(bytes32 agreementId) public view virtual returns (uint8);

    function getAssetPurpose(bytes32 agreementId) public view virtual returns (Configuration.ASSET_PURPOSE);

    /**
     * Returns the timestamp of the block at which a debt agreement was issued.
     */
    function getIssuanceBlockTimestamp(bytes32 agreementId) public view virtual returns (uint256 timestamp);

    function getLastRepaymentTimestamp(bytes32 agreementId) public view virtual returns (uint256 timestamp);

    /**
     * Returns the terms contract parameters of a given issuance
     */
    function getTermsContractParameters(bytes32 agreementId) public view virtual returns (bytes32);

    function getExpirationTimestamp(bytes32 agreementId) public view virtual returns (uint256);

    // Update timestamp of the last repayment from Debtor
    function updateLastRepaymentTimestamp(bytes32 agreementId, uint256 newTimestamp) public virtual;

    /// @dev Get principal payment info before start doing repayment
    function principalPaymentInfo(bytes32 agreementId)
        public
        view
        virtual
        returns (address pTokenAddress, uint256 pAmount);

    function setCompletedLoan(bytes32 agreementId) public virtual;
}
