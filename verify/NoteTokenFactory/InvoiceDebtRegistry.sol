// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import './CRDecisionEngine.sol';
import "../Unpack16.sol";
import "../Unpack.sol";
import "../ConfigHelper.sol";
import './Registry.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import './AcceptedInvoiceToken.sol';

/**
 * The CommodityDebtRegistry stores the parameters and beneficiaries of all debt agreements in
 * Binkabi protocol.  It authorizes a limited number of agents to
 * perform mutations on it -- those agents can be changed at any
 * time by the contract's owner.
 */
contract InvoiceDebtRegistry is Initializable, PausableUpgradeable, OwnableUpgradeable, CRDecisionEngine {
    using SafeMath for uint256;
    using ConfigHelper for Registry;
    using Unpack for bytes32;
    using Unpack16 for bytes16;

    struct Entry {
        address version; // address of current repayment router
        address beneficiary;
        address debtor;
        address termsContract;
        address principalTokenAddress;
        bytes32 termsContractParameters;
        uint256 issuanceBlockTimestamp;
        uint256 lastRepayTimestamp;
        uint256 expirationTimestamp;
        uint256 collateralRatio;
        uint256 minCollateralRatio;
    }

    Registry public registry;
    // Primary registry mapping agreement IDs to their corresponding entries
    mapping(bytes32 => Entry) internal entries;
    mapping(bytes32 => uint256[]) internal registryToInvoice;

    // Maps debtor addresses to a list of their debts' agreement IDs
    mapping(address => bytes32[]) internal debtorToDebts;

    // List of terms which have completed repayment
    mapping(bytes32 => bool) public completedRepayment;
    mapping(bytes32 => uint256) public repaidPrincipalAmount;
    mapping(bytes32 => uint256) public repaidInterestAmount;

    mapping(bytes32 => bool) public completedLoans;

    // Setting manual for interest amount
    mapping(bytes32 => bool) public manualInterestLoan;
    mapping(bytes32 => uint256) public manualInterestAmountLoan;

    //////////////////////////////
    // EVENTS                   //
    //////////////////////////////

    event LogInsertEntry(
        bytes32 indexed agreementId,
        address indexed beneficiary,
        address termsContract,
        bytes32 termsContractParameters
    );

    event LogModifyEntryBeneficiary(
        bytes32 indexed agreementId,
        address indexed previousBeneficiary,
        address indexed newBeneficiary
    );

    //////////////////////////////
    // MODIFIERS                //
    //////////////////////////////

    modifier nonNullBeneficiary(address beneficiary) {
        require(
            beneficiary != address(0),
            'Invoice Debt Registry: Beneficiary must be different with address 0.'
        );
        _;
    }

    modifier onlyExtantEntry(bytes32 agreementId) {
        require(
            doesEntryExist(agreementId),
            'Invoice Debt Registry: Agreement Id does not exists.'
        );
        _;
    }

    modifier onlyAuthorizedToEdit() {
        require(
            _msgSender() == address(registry.getInvoiceFinanceInterestTermsContract()),
            'Invoice Debt Registry: Sender does not have permission to edit.'
        );
        _;
    }

    function initialize(Registry _registry) public initializer {
        __Pausable_init_unchained();
        __Ownable_init_unchained();
        registry = _registry;
    }

    ////////////////////////////////////////////
    // INTERNAL FUNCTIONS                    //
    //////////////////////////////////////////
    /**
     * Helper function for computing the hash of a given issuance,
     * and, in turn, its agreementId
     */
    function _getAgreementId(
        Entry memory _entry,
        address _debtor,
        uint256 _salt
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    _entry.version,
                    _debtor,
                    _entry.termsContract,
                    _entry.termsContractParameters,
                    _salt
                )
            );
    }

    function _evaluateCollateralRatio(bytes32 agreementId) internal {
        uint256 invoiceAmount = _getTotalInvoiceAmount(agreementId);
        uint256 totalRemain = registry.getInvoiceFinanceInterestTermsContract()
            .getTotalExpectedRepaymentValue(agreementId, block.timestamp);

        uint256 cr = _computeInvoiceCR(invoiceAmount, totalRemain);

        uint256 previousCR = entries[agreementId].collateralRatio;

        if (cr != previousCR) {
            entries[agreementId].collateralRatio = cr;
        }
    }

    ///////////////////////////////////////////
    // CROSS-CONTRACT & EXTERNAL FUNCTIONS ///
    /////////////////////////////////////////
    //--------------
    // SENDs
    //--------------
    /**
     * TODO: Limitation for inserting
     * Inserts a new entry into the registry, if the entry is valid and sender is
     * authorized to make 'insert' mutations to the registry.
     */
    function insert(
        address _version,
        address _beneficiary,
        address _debtor,
        address _termsContract,
        address _principalTokenAddress,
        bytes32 _termsContractParameters,
        bytes32[] memory _invoiceTokenIds,
        uint256[3] memory values
    )
        public
        whenNotPaused
        nonNullBeneficiary(_beneficiary)
        returns (bytes32 _agreementId)
    {
        Entry memory entry = Entry({
            version: _version,
            beneficiary: _beneficiary,
            debtor: _debtor,
            termsContract: _termsContract,
            termsContractParameters: _termsContractParameters, //solium-disable-next-line security
            issuanceBlockTimestamp: block.timestamp,
            lastRepayTimestamp: 0,
            collateralRatio: 0,
            minCollateralRatio: values[0],
            expirationTimestamp: values[1],
            principalTokenAddress: _principalTokenAddress
        });
        bytes32 agreementId = _getAgreementId(entry, _debtor, values[2]); // entry, debtor, salt

        require(
            entries[agreementId].beneficiary == address(0),
            'Beneficiary account already exists.'
        );

        entries[agreementId] = entry;

        for (uint256 i = 0; i < _invoiceTokenIds.length; i++) {
            registryToInvoice[agreementId].push(uint256(_invoiceTokenIds[i]));
        }

        selfEvaluateCollateralRatio(agreementId);

        debtorToDebts[_debtor].push(agreementId);

        emit LogInsertEntry(
            agreementId,
            entry.beneficiary,
            entry.termsContract,
            entry.termsContractParameters
        );

        return agreementId;
    }

    /**
    * @dev TODO: Security restriction
    * Restriction: only if terms parameters is validated
    */
    function updateLoanTermParameters(
        bytes32 agreementId,
        bytes32 newLoanTermsParameters
    ) public {
        entries[agreementId].termsContractParameters = newLoanTermsParameters;
    }

    function setMinCollateralRatio(
        bytes32 agreementId,
        uint256 minCollateralRatio
    ) public {
        entries[agreementId].minCollateralRatio = minCollateralRatio;
    }

    //@TODO security restriction
    /**
     * Modifies the beneficiary of a debt issuance, if the sender
     * is authorized to make 'modifyBeneficiary' mutations to
     * the entries.
    */
    function modifyBeneficiary(bytes32 agreementId, address newBeneficiary)
        public
        whenNotPaused
        onlyExtantEntry(agreementId)
        nonNullBeneficiary(newBeneficiary)
    {
        address previousBeneficiary = entries[agreementId].beneficiary;
        entries[agreementId].beneficiary = newBeneficiary;

        emit LogModifyEntryBeneficiary(
            agreementId,
            previousBeneficiary,
            newBeneficiary
        );
    }

    function selfEvaluateCollateralRatio(bytes32 agreementId) public {
        _evaluateCollateralRatio(agreementId);
    }

    // Update timestamp of the last repayment from Debtor
    function updateLastRepaymentTimestamp(
        bytes32 agreementId,
        uint256 newTimestamp
    ) public onlyAuthorizedToEdit {
        entries[agreementId].lastRepayTimestamp = newTimestamp;
    }

    //-----------------
    // CALLs
    //-----------------

    /* Ensures an entry with the specified agreement ID exists within the debt entries. */
    function doesEntryExist(bytes32 agreementId)
        public
        view
        returns (bool exists)
    {
        return entries[agreementId].beneficiary != address(0);
    }

    /**
     * Returns the beneficiary of a given issuance
     */
    function getBeneficiary(bytes32 agreementId)
        public
        view
        onlyExtantEntry(agreementId)
        returns (address)
    {
        // Lender
        return entries[agreementId].beneficiary;
    }

    function getDebtor(bytes32 agreementId)
        public
        view
        onlyExtantEntry(agreementId)
        returns (address)
    {
        return entries[agreementId].debtor;
    }

    /**
     * Returns a tuple of the terms contract and its associated parameters
     * for a given issuance
    */
    function getTerms(bytes32 agreementId)
        public
        view
        onlyExtantEntry(agreementId)
        returns (address, bytes32)
    {
        return (
            entries[agreementId].termsContract,
            entries[agreementId].termsContractParameters
        );
    }

    function getInvoiceTokenIds(bytes32 agreementId)
        public
        view
        returns (uint256[] memory)
    {
        return registryToInvoice[agreementId];
    }

    function insertInvoiceFinancedToInvoiceLoan(
        bytes32 agreementId,
        uint256 invoiceTokenId
    ) public {
        registryToInvoice[agreementId].push(invoiceTokenId);
    }

    function removeInvoiceId(bytes32 agreementId, uint256 invoiceId) public {
        if (registryToInvoice[agreementId].length > 0) {
            for (
                uint256 i = 0;
                i < registryToInvoice[agreementId].length;
                ++i
            ) {
                if (registryToInvoice[agreementId][i] == invoiceId) {
                    // Remove i element from registryToInvoice[agreementId]
                    for (
                        uint256 index = i;
                        index < registryToInvoice[agreementId].length - 1;
                        index++
                    ) {
                        registryToInvoice[agreementId][index] = registryToInvoice[agreementId][index +
                            1];
                    }
                    registryToInvoice[agreementId].pop();

                    selfEvaluateCollateralRatio(agreementId);
                    break;
                }
            }
        }
    }

    function _getTotalInvoiceAmount(bytes32 agreementId)
        public
        view
        returns (uint256 amount)
    {
        AcceptedInvoiceToken acceptedInvoiceToken = registry.getAcceptedInvoiceToken();

        amount = 0;
        if (registryToInvoice[agreementId].length > 0) {
            for (
                uint256 i = 0;
                i < registryToInvoice[agreementId].length;
                ++i
            ) {
                if (
                    acceptedInvoiceToken.ownerOf(
                        registryToInvoice[agreementId][i]
                    ) != address(0)
                ) {
                    amount += acceptedInvoiceToken.getFiatAmount(
                        registryToInvoice[agreementId][i]
                    );
                }
            }
        }
    }

    /**
    * Returns the terms contract address of a given issuance
    */
    function getTermsContract(bytes32 agreementId)
        public
        view
        onlyExtantEntry(agreementId)
        returns (address)
    {
        return entries[agreementId].termsContract;
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
        return entries[agreementId].termsContractParameters;
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

    function getExpirationTimestamp(bytes32 agreementId)
        public
        view
        onlyExtantEntry(agreementId)
        returns (uint256)
    {
        // solhint-disable-next-line not-rely-on-time
        return entries[agreementId].expirationTimestamp;
    }

    /**
     * Returns the parameters of a debt issuance in the entries.
     *
     * TODO: protect this function with our `onlyExtantEntry` modifier once the restriction
     * on the size of the call stack has been addressed.
     */
    function get(bytes32 agreementId)
        public
        view
        returns (address, address, address, bytes32, uint256)
    {
        return (
            entries[agreementId].version,
            entries[agreementId].beneficiary,
            entries[agreementId].termsContract,
            entries[agreementId].termsContractParameters,
            entries[agreementId].issuanceBlockTimestamp
        );
    }

    function getCollateralRatio(bytes32 agreementId)
        public
        view
        returns (uint256)
    {
        return entries[agreementId].collateralRatio;
    }

    function getMinCollateralRatio(bytes32 agreementId)
        public
        view
        returns (uint256)
    {
        return entries[agreementId].minCollateralRatio;
    }

    function isCompletedRepayment(bytes32 agreementId)
        public
        view
        returns (bool)
    {
        return completedRepayment[agreementId];
    }

    function setCompletedRepayment(bytes32 agreementId) public {
        completedRepayment[agreementId] = true;
    }

    function getRepaidPrincipalAmount(bytes32 agreementId)
        public
        view
        returns (uint256)
    {
        return repaidPrincipalAmount[agreementId];
    }

    function addRepaidPrincipalAmount(bytes32 agreementId, uint256 repaidAmount)
        public
    {
        repaidPrincipalAmount[agreementId] = repaidPrincipalAmount[agreementId]
            .add(repaidAmount);
    }

    function setRepaidPrincipalAmount(bytes32 agreementId, uint256 repaidAmount)
        public
    {
        repaidPrincipalAmount[agreementId] = repaidAmount;
    }

    function getRepaidInterestAmount(bytes32 agreementId)
        public
        view
        returns (uint256)
    {
        return repaidInterestAmount[agreementId];
    }

    function addRepaidInterestAmount(bytes32 agreementId, uint256 repaidAmount)
        public
    {
        repaidInterestAmount[agreementId] = repaidInterestAmount[agreementId]
            .add(repaidAmount);
    }

    function setRepaidInterestAmount(bytes32 agreementId, uint256 repaidAmount)
        public
    {
        repaidInterestAmount[agreementId] = repaidAmount;
    }

    function getValueRepaidToDate(bytes32 agreementId)
        public
        view
        returns (uint256, uint256)
    {
        return (
            repaidPrincipalAmount[agreementId],
            repaidInterestAmount[agreementId]
        );
    }

    function isCompletedLoan(bytes32 agreementId) public view returns (bool) {
        return completedLoans[agreementId];
    }

    function setCompletedLoan(bytes32 agreementId) public {
        completedLoans[agreementId] = true;
    }

    function isManualInterestLoan(bytes32 agreementId)
        public
        view
        returns (bool)
    {
        return manualInterestLoan[agreementId];
    }

    function setManualInterestLoan(bytes32 agreementId, bool isManualInterest)
        public
    {
        manualInterestLoan[agreementId] = isManualInterest;
    }

    function getManualInterestAmountLoan(bytes32 agreementId)
        public
        view
        returns (uint256)
    {
        return manualInterestAmountLoan[agreementId];
    }

    function setManualInterestAmountLoan(
        bytes32 agreementId,
        uint256 interestAmount
    ) public {
        manualInterestAmountLoan[agreementId] = interestAmount;
    }

    function getAgreement(bytes32 agreementId) public view returns(Entry memory) {
        return entries[agreementId];
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
}
