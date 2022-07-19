// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../libraries/openzeppelin/Pausable.sol";
import "../../libraries/openzeppelin/Ownable.sol";
import "../../libraries/UnpackLoanParamtersLib.sol";
import "../CRInventoryEngineTypes.sol";
import "../CRInventoryDecisionEngine.sol";
import "../../libraries/PermissionsLib.sol";
import "../../token/invoice/AcceptedInvoiceToken.sol";
import "../../loan/inventory/InventoryInterestTermsContract.sol";
import "../../loan/inventory/InventoryLoanDebtKernel.sol";

contract InventoryLoanDebtRegistry is
    Pausable,
    BinkabiContext,
    UnpackLoanParamtersLib,
    CRInventoryEngineTypes,
    CRInventoryDecisionEngine
{
    using SafeMath for uint256;
    using PermissionsLib for PermissionsLib.Permissions;

    PermissionsLib.Permissions internal entryInsertPermissions;
    PermissionsLib.Permissions internal entryEditPermissions;

    struct Entry {
        address version; // address of current repayment router
        address beneficiary;
        address debtor;
        address termsContract;
        bytes32 termsContractParameters;
        bytes16 collateralInfoParameters;
        uint256 issuanceBlockTimestamp;
        uint256 lastRepayTimestamp;
        uint256 expirationTimestamp;
        CollateralRatioValues collateralRatioValues;
    }
    // Primary registry mapping agreement IDs to their corresponding entries
    mapping(bytes32 => Entry) internal registry;
    // Helper mapping agreement IDs to their corresponding invoice token id
    mapping(bytes32 => uint256[]) internal registryToInvoice;
    // Maps debtor addresses to a list of their debts' agreement IDs
    mapping(address => bytes32[]) internal debtorToDebts;
    // agreement id -> waiting for payment of sell collateral id -> sell info
    mapping (bytes32 => mapping (bytes32 => SellCollateralInfo)) public waitingSellCollateral;
    mapping (bytes32 => mapping (bytes32 => bool)) public waitingSellCollateralExisted;
    // agreement id -> is foreclosure
    mapping (bytes32 => bool) liquidatedLoan;

    // List of terms which have completed repayment
    mapping (bytes32 => bool) public completedRepayment;
    mapping (bytes32 => uint) public repaidPrincipalAmount;
    mapping (bytes32 => uint) public repaidInterestAmount;

    mapping (bytes32 => bool) public completedLoans;

    // Setting manual for interest amount
    mapping (bytes32 => bool) internal manualInterestLoan;
    mapping (bytes32 => uint) internal manualInterestAmountLoan;

    struct SellCollateralInfo {
        bytes32 agreementId;
        uint256 amountPayment;
        uint256 fiatTokenIndex;
    }

    //////////////////////////////
    // CONSTANTS               //
    ////////////////////////////
    string public constant INSERT_CONTEXT = "commodity-debt-registry-insert";
    string public constant EDIT_CONTEXT = "commodity-debt-registry-edit";

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

    event CollateralRatioChanged(
        bytes32 indexed agreementId,
        uint256 previousCR,
        uint256 latestCR
    );

    constructor(address contractRegistryAddress) public BinkabiContext(contractRegistryAddress) {
    }

    //////////////////////////////
    // MODIFIERS                //
    //////////////////////////////

    modifier nonNullBeneficiary(address beneficiary) {
        require(
            beneficiary != address(0),
            "Inventory Debt Registry: Beneficiary must be different with address 0."
        );
        _;
    }

    modifier onlyExtantEntry(bytes32 agreementId) {
        require(
            doesEntryExist(agreementId),
            "Inventory Debt Registry: Agreement Id does not exists."
        );
        _;
    }

    modifier onlyAuthorizedToInsert() {
        require(
            entryInsertPermissions.isAuthorized(msg.sender) || _isAuthorizedContract(msg.sender),
            "Inventory Debt Registry: Sender does not have permission to insert."
        );
        _;
    }

    modifier onlyAuthorizedToEdit() {
        require(
            entryEditPermissions.isAuthorized(msg.sender) || _isAuthorizedContract(msg.sender),
            "Inventory Debt Registry: Sender does not have permission to edit."
        );
        _;
    }

    modifier onlyPriceFeedOperator(bytes32 agreementId) {
        require(
            msg.sender ==
            registry[agreementId].collateralRatioValues.priceFeedOperator,
            "Inventory Debt Registry: Not authorized to update price."
        );
        _;
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

    function _evaluateCollateralRatio(bytes32 agreementId, uint256 price)
    internal
    {
        uint256 collateralAmount;
        (, collateralAmount) = _unpackInventoryCollateralParametersFromBytes(
            registry[agreementId].collateralInfoParameters
        );

        uint256 invoiceAmount = _getTotalInvoiceAmount(agreementId);

        uint256 currentTimestamp = block.timestamp;
        uint256 totalRemain = InventoryInterestTermsContract(contractRegistry.get(INVENTORY_INTEREST_TERMS_CONTRACT)).getTotalExpectedRepaymentValue(
            agreementId,
            currentTimestamp
        );

        uint256 cr = _computeCR(collateralAmount, price, invoiceAmount, totalRemain);

        uint256 previousCR = registry[agreementId].collateralRatioValues.lastCollateralRatio;

        if (cr != previousCR) {
            registry[agreementId]
                .collateralRatioValues
                .lastCollateralRatio = cr;
            emit CollateralRatioChanged(agreementId, previousCR, cr);
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
        address _priceFeedOperator,
        bytes32 _termsContractParameters,
        bytes16 _collateralInfoParameters,
        uint256[4] memory values
    )
    public
    whenNotPaused
    nonNullBeneficiary(_beneficiary)
    returns (bytes32)
    {
        CollateralRatioValues memory crValues = CollateralRatioValues({
            priceFeedOperator: _priceFeedOperator,
            initCollateralRatio: 0,
            lastCollateralRatio: 0,
            minCollateralRatio: values[0],
            liquidationRatio: values[1]
        });

        Entry memory entry = Entry({
            version: _version,
            beneficiary: _beneficiary,
            debtor: _debtor,
            termsContract: _termsContract,
            termsContractParameters: _termsContractParameters,
            collateralInfoParameters: _collateralInfoParameters,
            // solium-disable-next-line security
            issuanceBlockTimestamp: block.timestamp,
            lastRepayTimestamp: 0,
            expirationTimestamp: values[2],
            collateralRatioValues: crValues
        });
        bytes32 agreementId = _getAgreementId(entry, _debtor, values[3]);

        require(
            registry[agreementId].beneficiary == address(0),
            "Beneficiary account already exists."
        );

        registry[agreementId] = entry;

        selfEvaluateCollateralRatio(agreementId);
        registry[agreementId]
            .collateralRatioValues
            .initCollateralRatio = registry[agreementId].collateralRatioValues.lastCollateralRatio;

        debtorToDebts[_debtor].push(agreementId);

        emit LogInsertEntry(
            agreementId,
            entry.beneficiary,
            entry.termsContract,
            entry.termsContractParameters
        );

        return agreementId;
    }

    function insertInvoiceFinancedToInventoryLoan(bytes32 agreementId, uint256 invoiceTokenId) public {
        registryToInvoice[agreementId].push(invoiceTokenId);
    }

    /**
    * Price Feed Operator will call this function to evaluate the CR and update Liquidation satus
    */
    function evaluateCollateralRatio(
        bytes32 agreementId,
        uint256 price,
        uint256 _timestamp
    ) public onlyPriceFeedOperator(agreementId) returns (bool) {
        require(_verifyPrice(_timestamp), "Inventory Debt Registry: Invalid price data.");
        _evaluateCollateralRatio(agreementId, price);
        return true;
    }

    function selfEvaluateCollateralRatio(bytes32 agreementId)
    public
    returns (bool)
    {
        uint256 lastPrice = getCollateralLastPrice(agreementId);
        _evaluateCollateralRatio(agreementId, lastPrice);
        return true;
    }

    /**
    * @dev TODO: Security restriction
    * Restriction: only if terms parameters is validated
    */
    function updateLoanTermParameters(
        bytes32 agreementId,
        bytes32 newLoanTermsParameters
    ) public {
        registry[agreementId].termsContractParameters = newLoanTermsParameters;
    }

    /**
    * @dev TODO: Security restriction
    */
    function updateCollateralInfoParameters(
        bytes32 agreementId,
        bytes16 newCollateralInfoParameters
    ) public {
        registry[agreementId].collateralInfoParameters = newCollateralInfoParameters;

        uint256 collateralAmount;
        (, collateralAmount) = _unpackInventoryCollateralParametersFromBytes(
            newCollateralInfoParameters
        );

        require(
            collateralAmount >= 0,
            "Inventory Debt Registry: Invalid new collateral info parameters."
        );
    }

    function setMinCollateralRatio(bytes32 agreementId, uint256 minCollateralRatio) public {
        registry[agreementId].collateralRatioValues.minCollateralRatio = minCollateralRatio;
    }

    function setLiquidationRatio(bytes32 agreementId, uint256 liquidationRatio) public {
        registry[agreementId].collateralRatioValues.liquidationRatio = liquidationRatio;
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
        address previousBeneficiary = registry[agreementId].beneficiary;
        registry[agreementId].beneficiary = newBeneficiary;

        emit LogModifyEntryBeneficiary(
            agreementId,
            previousBeneficiary,
            newBeneficiary
        );
    }

    /**
     * Adds an address to the list of agents authorized
     * to make 'insert' mutations to the registry.
     */
    function addAuthorizedInsertAgent(address agent) public onlyOwner {
        entryInsertPermissions.authorize(agent, INSERT_CONTEXT);
    }

    /**
     * Adds an address to the list of agents authorized
     * to make 'modifyBeneficiary' mutations to the registry.
     */
    function addAuthorizedEditAgent(address agent) public onlyOwner {
        entryEditPermissions.authorize(agent, EDIT_CONTEXT);
    }

    /**
     * Removes an address from the list of agents authorized
     * to make 'insert' mutations to the registry.
     */
    function revokeInsertAgentAuthorization(address agent) public onlyOwner {
        entryInsertPermissions.revokeAuthorization(agent, INSERT_CONTEXT);
    }

    /**
     * Removes an address from the list of agents authorized
     * to make 'modifyBeneficiary' mutations to the registry.
     */
    function revokeEditAgentAuthorization(address agent) public onlyOwner {
        entryEditPermissions.revokeAuthorization(agent, EDIT_CONTEXT);
    }

    // Update timestamp of the last repayment from Debtor
    function updateLastRepaymentTimestamp(bytes32 agreementId, uint newTimestamp)
    public
    onlyAuthorizedToEdit
    {
        registry[agreementId].lastRepayTimestamp = newTimestamp;
    }

    //-----------------
    // CALLs
    //-----------------

    /* Ensures an entry with the specified agreement ID exists within the debt registry. */
    function doesEntryExist(bytes32 agreementId)
    public
    view
    returns (bool)
    {
        return registry[agreementId].beneficiary != address(0);
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
        return registry[agreementId].beneficiary;
    }

    function getDebtor(bytes32 agreementId)
    public
    view
    onlyExtantEntry(agreementId)
    returns (address)
    {
        return registry[agreementId].debtor;
    }

    /**
     * Returns a tuple of the terms contract and its associated parameters
     * for a given issuance
    */
    function getTerms(bytes32 agreementId)
    public
    view
    onlyExtantEntry(agreementId)
    returns (address, bytes32, bytes16)
    {
        return (
            registry[agreementId].termsContract,
            registry[agreementId].termsContractParameters,
            registry[agreementId].collateralInfoParameters
        );
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
        return registry[agreementId].termsContract;
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
        return registry[agreementId].termsContractParameters;
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
        return registry[agreementId].issuanceBlockTimestamp;
    }

    function getLastRepaymentTimestamp(bytes32 agreementId)
    public
    view
    onlyExtantEntry(agreementId)
    returns (uint256 timestamp)
    {
        return registry[agreementId].lastRepayTimestamp;
    }

    function getExpirationTimestamp(bytes32 agreementId)
    public
    view
    onlyExtantEntry(agreementId)
    returns (uint256)
    {
        // solhint-disable-next-line not-rely-on-time
        return registry[agreementId].expirationTimestamp;
    }

    /**
     * Returns the parameters of a debt issuance in the registry.
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
            registry[agreementId].version,
            registry[agreementId].beneficiary,
            registry[agreementId].termsContract,
            registry[agreementId].termsContractParameters,
            registry[agreementId].issuanceBlockTimestamp
        );
    }

    function getLiquidationRatio(bytes32 agreementId)
    public
    view
    returns (uint256)
    {
        return registry[agreementId].collateralRatioValues.liquidationRatio;
    }

    function getMinCollateralRatio(bytes32 agreementId)
    public view
    returns (uint256)
    {
        return registry[agreementId].collateralRatioValues.minCollateralRatio;
    }

    function getCollateralLastPrice(bytes32 agreementId) public view returns (uint256) {
        (uint collateralId,) = _unpackInventoryCollateralParametersFromBytes(
            registry[agreementId].collateralInfoParameters
        );

        return SupplyChainManagementProgram(contractRegistry.get(SUPPLY_CHAIN_MANAGEMENT_PROGRAM)).getCommodityPrice(collateralId);
    }

    function getInitCollateralRatio(bytes32 agreementId)
    public
    view
    returns (uint256)
    {
        return registry[agreementId].collateralRatioValues.initCollateralRatio;
    }

    function isReadyForLiquidation(bytes32 agreementId)
    public
    view
    returns (bool)
    {
        return registry[agreementId].collateralRatioValues.liquidationRatio >= registry[agreementId].collateralRatioValues.lastCollateralRatio;
    }

    function latestCollateralRatio(bytes32 agreementId)
    public
    view
    returns (uint256)
    {
        return registry[agreementId].collateralRatioValues.lastCollateralRatio;
    }

    function getCollateralInfoParameters(bytes32 agreementId)
    public
    view
    returns (uint256 collateralId, uint256 collateralAmount)
    {
        (collateralId, collateralAmount) = _unpackInventoryCollateralParametersFromBytes(
            registry[agreementId].collateralInfoParameters
        );
    }

    function getTermsContractParametersInfo(bytes32 agreementId)
    public
    view
    returns (
        uint principalTokenIndex,
        uint principalAmount,
        uint interestRate,
        uint termLengthInAmortizationUnits
    )
    {
        (principalTokenIndex, principalAmount, interestRate,, termLengthInAmortizationUnits,) = _unpackLoanTermsParametersFromBytes(
            registry[agreementId].termsContractParameters
        );
    }

    function getInvoiceIds(bytes32 agreementId) public view returns (uint256[] memory) {
        return registryToInvoice[agreementId];
    }

    function removeInvoiceId(bytes32 agreementId, uint256 invoiceId) public {
        if (registryToInvoice[agreementId].length > 0) {
            for (uint i = 0; i < registryToInvoice[agreementId].length; ++i) {
                if (registryToInvoice[agreementId][i] == invoiceId) {

                    // Remove i element from registryToInvoice[agreementId]
                    for (uint index = i; index<registryToInvoice[agreementId].length-1; index++){
                        registryToInvoice[agreementId][index] = registryToInvoice[agreementId][index+1];
                    }
                    delete registryToInvoice[agreementId][registryToInvoice[agreementId].length-1];
                    registryToInvoice[agreementId].length--;

                    selfEvaluateCollateralRatio(agreementId);
                    break;
                }
            }
        }
    }

    function _getTotalInvoiceAmount(bytes32 agreementId) public view returns (uint256 amount) {
        AcceptedInvoiceToken acceptedInvoiceToken = AcceptedInvoiceToken(contractRegistry.get(ACCEPTED_INVOICE_TOKEN));

        amount = 0;
        if (registryToInvoice[agreementId].length > 0) {
            for (uint i = 0; i < registryToInvoice[agreementId].length; ++i) {
                amount += acceptedInvoiceToken.getFiatAmount(registryToInvoice[agreementId][i]);
            }
        }
    }

    function setWaitingSellCollateral(bytes32 agreementId, bytes32 sellId, uint256 amount, uint256 fiatTokenIndex)
        public
    {
        SellCollateralInfo memory sellCollateralInfo = SellCollateralInfo({
            agreementId: agreementId,
            amountPayment: amount,
            fiatTokenIndex: fiatTokenIndex
        });
        waitingSellCollateral[agreementId][sellId] = sellCollateralInfo;
        waitingSellCollateralExisted[agreementId][sellId] = true;
    }

    function isWaitingSellCollateralExisted(bytes32 agreementId, bytes32 sellId) public view returns (bool) {
        return waitingSellCollateralExisted[agreementId][sellId];
    }

    function getWaitingSellCollateral(bytes32 _agreementId, bytes32 _sellId)
        public view
        returns (uint256 amountPayment, uint256 fiatTokenIndex)
    {
        SellCollateralInfo memory sellInfo = waitingSellCollateral[_agreementId][_sellId];
        return (sellInfo.amountPayment, sellInfo.fiatTokenIndex);
    }

    function isLoanLiquidated(bytes32 agreementId) public view returns (bool) {
        return liquidatedLoan[agreementId];
    }

    function setLoanLiquidated(bytes32 agreementId) public {
        liquidatedLoan[agreementId] = true;
    }

    function removeLiquidatedLoan(bytes32 agreementId) public {
        delete liquidatedLoan[agreementId];
    }

    function isExpiredOrReadyForLiquidation(bytes32 agreementId) public view returns (bool){
        uint expTimestamp = registry[agreementId].expirationTimestamp;
        // solium-disable-next-line
        if (expTimestamp <= block.timestamp) {
            return true;
        }

        return isReadyForLiquidation(agreementId);
    }

    function isCompletedRepayment(bytes32 agreementId) public view returns (bool) {
        return completedRepayment[agreementId];
    }

    function setCompletedRepayment(bytes32 agreementId) public {
        completedRepayment[agreementId] = true;
    }

    function getRepaidPrincipalAmount(bytes32 agreementId) public view returns (uint) {
        return repaidPrincipalAmount[agreementId];
    }

    function addRepaidPrincipalAmount(bytes32 agreementId, uint repaidAmount) public {
        repaidPrincipalAmount[agreementId] = repaidPrincipalAmount[agreementId].add(repaidAmount);
    }

    function setRepaidPrincipalAmount(bytes32 agreementId, uint repaidAmount) public {
        repaidPrincipalAmount[agreementId] = repaidAmount;
    }

    function getRepaidInterestAmount(bytes32 agreementId) public view returns (uint) {
        return repaidInterestAmount[agreementId];
    }

    function addRepaidInterestAmount(bytes32 agreementId, uint repaidAmount) public {
        repaidInterestAmount[agreementId] = repaidInterestAmount[agreementId].add(repaidAmount);
    }

    function setRepaidInterestAmount(bytes32 agreementId, uint repaidAmount) public {
        repaidInterestAmount[agreementId] = repaidAmount;
    }

    function getValueRepaidToDate(bytes32 agreementId) public view returns (uint, uint) {
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

    function isManualInterestLoan(bytes32 agreementId) public view returns (bool) {
        return manualInterestLoan[agreementId];
    }

    function setManualInterestLoan(bytes32 agreementId, bool isManualInterest) public {
        manualInterestLoan[agreementId] = isManualInterest;
    }

    function getManualInterestAmountLoan(bytes32 agreementId) public view returns (uint) {
        return manualInterestAmountLoan[agreementId];
    }

    function setManualInterestAmountLoan(bytes32 agreementId, uint interestAmount) public {
        manualInterestAmountLoan[agreementId] = interestAmount;
    }
}
