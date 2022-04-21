pragma solidity ^0.8.0;

import '../storage/Registry.sol';

abstract contract IExternalLoanDebtRegistry is UntangledBase {
    Registry public registry;

    // loan -> debtors
    struct ExternalLoanEntry {
        address lender;
        address loanTermContract;
        address debtor;
        bytes32 termsParam; // actually inside this param was already included P token index
        uint256 principalTokenIndex;
        uint256 salt;
        uint256 issuanceBlockTimestamp;
        uint256 lastRepayTimestamp;
        uint256 expirationTimestamp;
        uint8 riskScore;
        AssetPurpose assetPurpose;
    }
    enum AssetPurpose {SALE, PLEDGE}

    mapping(bytes32 => ExternalLoanEntry) entries;

    mapping(bytes32 => bool) internal manualInterestLoan;
    mapping(bytes32 => uint256) internal manualInterestAmountLoan;

    mapping(bytes32 => bool) public completedLoans;

    function initialize(
        address owner,
        Registry _registry
    ) public virtual;

    // Validate the availabiliy of Debtor
    function _isDebtorOfLoan(bytes32 tokenId, address debtor) internal view virtual returns (bool);

    /**
     * Record new External Loan to blockchain
     */
    function insert(
        bytes32 tokenId,
        address beneficiary,
        address termContract,
        address debtor,
        bytes32 termsContractParameter,
        uint256 pTokenIndex,
        uint256 _salt,
        uint256 expirationTimestampInSecs,
        uint8[] calldata assetPurposeAndRiskScore
    ) external virtual returns (bool);

    /**
     * Modifies the beneficiary of a debt issuance, if the sender
     * is authorized to make 'modifyBeneficiary' mutations to
     * the registry.
     */
    function modifyBeneficiary(bytes32 agreementId, address newBeneficiary)
    public virtual;

    function getLoanDebtor(bytes32 tokenId) public view returns (address) {
        return entries[tokenId].debtor;
    }

    function getLoanTermParams(bytes32 tokenId, address debtor) public view virtual returns (bytes32);

    function getPrincipalTokenIndex(bytes32 agreementId) public view virtual returns (uint256);

    function getBeneficiary(bytes32 agreementId) public view virtual returns (address);

    function getDebtor(bytes32 agreementId) public view virtual returns (address);

    function getTermContract(bytes32 agreementId) public view virtual returns (address);

    function getRiskScore(bytes32 agreementId) public view virtual returns (uint8);

    function getAssetPurpose(bytes32 agreementId) public view virtual returns (uint8);

    function doesEntryExist(bytes32 agreementId) public view virtual returns (bool);

    /**
     * Returns the timestamp of the block at which a debt agreement was issued.
     */
    function getIssuanceBlockTimestamp(bytes32 agreementId)
        public
        view virtual
        returns (uint256 timestamp);

    function getLastRepaymentTimestamp(bytes32 agreementId)
        public
        view virtual
        returns (uint256 timestamp);

    function isManualInterestLoan(bytes32 agreementId) public view virtual returns (bool);

    function getManualInterestAmountLoan(bytes32 agreementId) public view virtual returns (uint256);

    /**
     * Returns the terms contract parameters of a given issuance
     */
    function getTermsContractParameters(bytes32 agreementId)
    public
    view virtual
    returns (bytes32);

    function getExpirationTimestamp(bytes32 agreementId) public view virtual returns (uint256);

    // Update timestamp of the last repayment from Debtor
    function updateLastRepaymentTimestamp(bytes32 agreementId, uint256 newTimestamp) public virtual;

    /// @dev Get principal payment info before start doing repayment
    function principalPaymentInfo(bytes32 agreementId)
    public
    view virtual
    returns (
        uint256 pTokenIndex,
        uint256 pAmount,
        address receiver
    );

    function setCompletedLoan(bytes32 agreementId) public virtual;

    function isCompletedLoan(bytes32 agreementId) public view virtual returns (bool);
}
