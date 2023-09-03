// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../../interfaces/ILoanRegistry.sol';
import '../../base/UntangledBase.sol';
import '../../libraries/ConfigHelper.sol';

/// @title LoanRegistry
/// @author Untangled Team
/// @dev Store LoanAssetToken information
contract LoanRegistry is UntangledBase, ILoanRegistry {
    using ConfigHelper for Registry;

    /** CONSTRUCTOR */
    function initialize(Registry _registry) public override initializer {
        __UntangledBase__init(_msgSender());
        registry = _registry;
    }

    modifier onlyLoanKernel() {
        require(_msgSender() == address(registry.getLoanKernel()), 'LoanRegistry: Only LoanKernel');
        _;
    }

    modifier onlyLoanInterestTermsContract() {
        require(
            _msgSender() == address(registry.getLoanInterestTermsContract()),
            'Invoice Debt Registry: Only LoanInterestTermsContract'
        );
        _;
    }

    /**
     * Record new Loan to blockchain
     */
    /// @dev Records a new loan entry by inserting loan details into the entries mapping
    function insert(
        bytes32 tokenId,
        address termContract,
        address debtor,
        bytes32 termsContractParameter,
        address pTokenAddress,
        uint256 _salt,
        uint256 expirationTimestampInSecs,
        uint8[] calldata assetPurposeAndRiskScore
    ) external override whenNotPaused nonReentrant onlyLoanKernel returns (bool) {
        require(termContract != address(0x0), 'LoanRegistry: Invalid term contract');
        LoanEntry memory newEntry = LoanEntry({
            loanTermContract: termContract,
            debtor: debtor,
            principalTokenAddress: pTokenAddress,
            termsParam: termsContractParameter,
            salt: _salt, //solium-disable-next-line security
            issuanceBlockTimestamp: block.timestamp,
            lastRepayTimestamp: 0,
            expirationTimestamp: expirationTimestampInSecs,
            assetPurpose: Configuration.ASSET_PURPOSE(assetPurposeAndRiskScore[0]),
            riskScore: assetPurposeAndRiskScore[1]
        });
        entries[tokenId] = newEntry;
        return true;
    }

    /// @inheritdoc ILoanRegistry
    function getLoanDebtor(bytes32 tokenId) public view override returns (address) {
        return entries[tokenId].debtor;
    }

    /// @inheritdoc ILoanRegistry
    function getLoanTermParams(bytes32 tokenId) public view override returns (bytes32) {
        LoanEntry memory entry = entries[tokenId];
        return entry.termsParam;
    }

    /// @inheritdoc ILoanRegistry
    function getPrincipalTokenAddress(bytes32 agreementId) public view override returns (address) {
        return entries[agreementId].principalTokenAddress;
    }

    /// @inheritdoc ILoanRegistry
    function getDebtor(bytes32 agreementId) public view override returns (address) {
        return entries[agreementId].debtor;
    }

    /// @inheritdoc ILoanRegistry
    function getTermContract(bytes32 agreementId) public view override returns (address) {
        return entries[agreementId].loanTermContract;
    }

    /// @inheritdoc ILoanRegistry
    function getRiskScore(bytes32 agreementId) public view override returns (uint8) {
        return entries[agreementId].riskScore;
    }

    /// @inheritdoc ILoanRegistry
    function getAssetPurpose(bytes32 agreementId) public view override returns (Configuration.ASSET_PURPOSE) {
        return entries[agreementId].assetPurpose;
    }

    /**
     * Returns the timestamp of the block at which a debt agreement was issued.
     */
    /// @inheritdoc ILoanRegistry
    function getIssuanceBlockTimestamp(bytes32 agreementId) public view override returns (uint256 timestamp) {
        return entries[agreementId].issuanceBlockTimestamp;
    }

    /// @inheritdoc ILoanRegistry
    function getLastRepaymentTimestamp(bytes32 agreementId) public view override returns (uint256 timestamp) {
        return entries[agreementId].lastRepayTimestamp;
    }

    /**
     * Returns the terms contract parameters of a given issuance
     */
    /// @inheritdoc ILoanRegistry
    function getTermsContractParameters(bytes32 agreementId) public view override returns (bytes32) {
        return entries[agreementId].termsParam;
    }

    /// @inheritdoc ILoanRegistry
    function getExpirationTimestamp(bytes32 agreementId) public view override returns (uint256) {
        // solhint-disable-next-line not-rely-on-time
        return entries[agreementId].expirationTimestamp;
    }

    // Update timestamp of the last repayment from Debtor
    /// @inheritdoc ILoanRegistry
    function updateLastRepaymentTimestamp(bytes32 agreementId, uint256 newTimestamp)
        public
        override
        onlyLoanInterestTermsContract
    {
        entries[agreementId].lastRepayTimestamp = newTimestamp;
    }

    /// @dev Get principal payment info before start doing repayment
    function principalPaymentInfo(bytes32 agreementId)
        public
        view
        override
        returns (address pTokenAddress, uint256 pAmount)
    {
        LoanEntry memory entry = entries[agreementId];
        pTokenAddress = entry.principalTokenAddress;
        pAmount = 0; // @TODO
    }

    /// @inheritdoc ILoanRegistry
    function setCompletedLoan(bytes32 agreementId) public override whenNotPaused nonReentrant onlyLoanInterestTermsContract {
        completedLoans[agreementId] = true;
    }
}
