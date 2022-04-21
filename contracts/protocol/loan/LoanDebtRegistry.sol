// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../../base/UntangledBase.sol';
import '../../libraries/ConfigHelper.sol';

contract LoanDebtRegistry is UntangledBase {
    using ConfigHelper for Registry;

    // loan -> debtors
    struct LoanEntry {
        address lender;
        address loanTermContract;
        address debtor;
        bytes32 termsParam; // actually inside this param was already included P token index
        address principalTokenAddress;
        uint256 salt;
        uint256 issuanceBlockTimestamp;
        uint256 lastRepayTimestamp;
        uint256 expirationTimestamp;
        uint8 riskScore;
        AssetPurpose assetPurpose;
    }
    enum AssetPurpose {
        SALE,
        PLEDGE
    }

    mapping(bytes32 => LoanEntry) entries;

    mapping(bytes32 => bool) internal manualInterestLoan;
    mapping(bytes32 => uint256) internal manualInterestAmountLoan;

    mapping(bytes32 => bool) public completedLoans;

    modifier nonNullBeneficiary(address beneficiary) {
        require(beneficiary != address(0), 'External Debt Registry: Beneficiary must be different with address 0.');
        _;
    }

    modifier onlyExtantEntry(bytes32 agreementId) {
        require(doesEntryExist(agreementId), 'External Debt Registry: Agreement Id does not exists.');
        _;
    }

    /** CONSTRUCTOR */
    function initialize(address owner, Registry _registry) public override initializer {
        __UntangledBase__init(owner);
        registry = _registry;
    }

    // Validate the availabiliy of Debtor
    function _isDebtorOfLoan(bytes32 tokenId, address debtor) internal view returns (bool) {
        if (entries[tokenId].debtor == debtor) {
            return true;
        }
        return false;
    }

    modifier onlyExternalLoanInterestTermsContract() {
        require(
            _msgSender() == address(registry.getExternalLoanInterestTermsContract()),
            'Invoice Debt Registry: Only ExternalLoanInterestTermsContract'
        );
        _;
    }

    /**
     * Record new External Loan to blockchain
     */
    function insert(
        bytes32 tokenId,
        address beneficiary,
        address termContract,
        address debtor,
        bytes32 termsContractParameter,
        address pTokenAddress,
        uint256 _salt,
        uint256 expirationTimestampInSecs,
        uint8[] calldata assetPurposeAndRiskScore
    ) external returns (bool) {
        require(termContract != address(0x0), 'Registry: Invalid term contract');
        ExternalLoanEntry memory newEntry = ExternalLoanEntry({
            lender: beneficiary,
            loanTermContract: termContract,
            debtor: debtor,
            principalTokenAddress: pTokenAddress,
            termsParam: termsContractParameter,
            salt: _salt, //solium-disable-next-line security
            issuanceBlockTimestamp: block.timestamp,
            lastRepayTimestamp: 0,
            expirationTimestamp: expirationTimestampInSecs,
            assetPurpose: AssetPurpose(assetPurposeAndRiskScore[0]),
            riskScore: assetPurposeAndRiskScore[1]
        });
        entries[tokenId] = newEntry;
        return true;
    }

    /**
     * Modifies the beneficiary of a debt issuance, if the sender
     * is authorized to make 'modifyBeneficiary' mutations to
     * the registry.
     */
    function modifyBeneficiary(bytes32 agreementId, address newBeneficiary)
        public
        whenNotPaused
        onlyExtantEntry(agreementId)
        nonNullBeneficiary(newBeneficiary)
    {
        entries[agreementId].lender = newBeneficiary;
    }

    function getLoanDebtor(bytes32 tokenId) public view returns (address) {
        return entries[tokenId].debtor;
    }

    function getLoanTermParams(bytes32 tokenId, address debtor) public view returns (bytes32) {
        bool isDebtor = _isDebtorOfLoan(tokenId, debtor);
        require(isDebtor, 'ELDebtRegistry: account is not debtor of this loan.');
        ExternalLoanEntry memory entry = entries[tokenId];
        return entry.termsParam;
    }

    function getPrincipalTokenAddress(bytes32 agreementId) public view returns (address) {
        return entries[agreementId].principalTokenAddress;
    }

    function getBeneficiary(bytes32 agreementId) public view returns (address) {
        return entries[agreementId].lender;
    }

    function getDebtor(bytes32 agreementId) public view onlyExtantEntry(agreementId) returns (address) {
        return entries[agreementId].debtor;
    }

    function getTermContract(bytes32 agreementId) public view returns (address) {
        return entries[agreementId].loanTermContract;
    }

    function getRiskScore(bytes32 agreementId) public view returns (uint8) {
        return entries[agreementId].riskScore;
    }

    function getAssetPurpose(bytes32 agreementId) public view returns (uint8) {
        return uint8(entries[agreementId].assetPurpose);
    }

    function doesEntryExist(bytes32 agreementId) public view returns (bool) {
        return entries[agreementId].lender != address(0);
    }

    /**
     * Returns the timestamp of the block at which a debt agreement was issued.
     */
    function getIssuanceBlockTimestamp(bytes32 agreementId)
        public
        view
        onlyExtantEntry(agreementId)
        returns (uint256 timestamp)
    {
        return entries[agreementId].issuanceBlockTimestamp;
    }

    function getLastRepaymentTimestamp(bytes32 agreementId)
        public
        view
        onlyExtantEntry(agreementId)
        returns (uint256 timestamp)
    {
        return entries[agreementId].lastRepayTimestamp;
    }

    function isManualInterestLoan(bytes32 agreementId) public view returns (bool) {
        return manualInterestLoan[agreementId];
    }

    function getManualInterestAmountLoan(bytes32 agreementId) public view returns (uint256) {
        return manualInterestAmountLoan[agreementId];
    }

    /**
     * Returns the terms contract parameters of a given issuance
     */
    function getTermsContractParameters(bytes32 agreementId)
        public
        view
        onlyExtantEntry(agreementId)
        returns (bytes32)
    {
        return entries[agreementId].termsParam;
    }

    function getExpirationTimestamp(bytes32 agreementId) public view onlyExtantEntry(agreementId) returns (uint256) {
        // solhint-disable-next-line not-rely-on-time
        return entries[agreementId].expirationTimestamp;
    }

    // Update timestamp of the last repayment from Debtor
    function updateLastRepaymentTimestamp(bytes32 agreementId, uint256 newTimestamp)
        public
        onlyExternalLoanInterestTermsContract
    {
        entries[agreementId].lastRepayTimestamp = newTimestamp;
    }

    /// @dev Get principal payment info before start doing repayment
    function principalPaymentInfo(bytes32 agreementId)
        public
        view
        returns (
            address pTokenAddress,
            uint256 pAmount,
            address receiver
        )
    {
        ExternalLoanEntry memory entry = entries[agreementId];
        pTokenAddress = entry.principalTokenAddress;
        pAmount = 0; // @TODO
        receiver = entry.lender;
    }

    function setCompletedLoan(bytes32 agreementId) public {
        completedLoans[agreementId] = true;
    }

    function isCompletedLoan(bytes32 agreementId) public view returns (bool) {
        return completedLoans[agreementId];
    }
}
