// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import '../../interfaces/ILoanRegistry.sol';
import '../../base/UntangledBase.sol';
import '../../libraries/ConfigHelper.sol';

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

    function getLoanDebtor(bytes32 tokenId) public view override returns (address) {
        return entries[tokenId].debtor;
    }

    function getLoanTermParams(bytes32 tokenId) public view override returns (bytes32) {
        LoanEntry memory entry = entries[tokenId];
        return entry.termsParam;
    }

    function getPrincipalTokenAddress(bytes32 agreementId) public view override returns (address) {
        return entries[agreementId].principalTokenAddress;
    }

    function getDebtor(bytes32 agreementId) public view override returns (address) {
        return entries[agreementId].debtor;
    }

    function getTermContract(bytes32 agreementId) public view override returns (address) {
        return entries[agreementId].loanTermContract;
    }

    function getRiskScore(bytes32 agreementId) public view override returns (uint8) {
        return entries[agreementId].riskScore;
    }

    function getAssetPurpose(bytes32 agreementId) public view override returns (Configuration.ASSET_PURPOSE) {
        return entries[agreementId].assetPurpose;
    }

    /**
     * Returns the timestamp of the block at which a debt agreement was issued.
     */
    function getIssuanceBlockTimestamp(bytes32 agreementId) public view override returns (uint256 timestamp) {
        return entries[agreementId].issuanceBlockTimestamp;
    }

    function getLastRepaymentTimestamp(bytes32 agreementId) public view override returns (uint256 timestamp) {
        return entries[agreementId].lastRepayTimestamp;
    }

    /**
     * Returns the terms contract parameters of a given issuance
     */
    function getTermsContractParameters(bytes32 agreementId) public view override returns (bytes32) {
        return entries[agreementId].termsParam;
    }

    function getExpirationTimestamp(bytes32 agreementId) public view override returns (uint256) {
        // solhint-disable-next-line not-rely-on-time
        return entries[agreementId].expirationTimestamp;
    }

    // Update timestamp of the last repayment from Debtor
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

    function setCompletedLoan(bytes32 agreementId) public override whenNotPaused nonReentrant onlyLoanInterestTermsContract {
        completedLoans[agreementId] = true;
    }
}
