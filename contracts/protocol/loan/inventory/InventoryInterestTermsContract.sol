// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './InventoryCollateralizer.sol';
import './InventoryLoanRegistry.sol';
import './InventoryLoanRepaymentRouter.sol';
import "../../../libraries/UnpackLoanParamtersLib.sol";
import "../LoanTyping.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../../../libraries/Unpack.sol";
import "../../../libraries/Unpack16.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../../../protocol/loan/inventory/CRInventoryDecisionEngine.sol";

contract InventoryInterestTermsContract is
    CRInventoryDecisionEngine, LoanTyping, PausableUpgradeable, OwnableUpgradeable
{
    using SafeMath for uint;
    using ConfigHelper for Registry;
    using Unpack for bytes32;
    using Unpack16 for bytes16;

    Registry public registry;
    uint256 public constant NUM_AMORTIZATION_UNIT_TYPES = 6;

    uint256 public constant YEAR_LENGTH_IN_DAYS = 365;
    // All time units in seconds
    uint256 public constant MINUTE_LENGTH_IN_SECONDS = 60;
    uint256 public constant HOUR_LENGTH_IN_SECONDS = MINUTE_LENGTH_IN_SECONDS * 60;
    uint256 public constant DAY_LENGTH_IN_SECONDS = HOUR_LENGTH_IN_SECONDS * 24;
    uint256 public constant WEEK_LENGTH_IN_SECONDS = DAY_LENGTH_IN_SECONDS * 7;
    uint256 public constant MONTH_LENGTH_IN_SECONDS = DAY_LENGTH_IN_SECONDS * 30;
    uint256 public constant YEAR_LENGTH_IN_SECONDS = DAY_LENGTH_IN_SECONDS * YEAR_LENGTH_IN_DAYS;

    // To convert an encoded interest rate into its equivalent in percents,
    // divide it by INTEREST_RATE_SCALING_FACTOR_PERCENT -- e.g.
    //     10,000 => 1% interest rate
    uint256 public constant INTEREST_RATE_SCALING_FACTOR_PERCENT = 10**4;

    // To convert an encoded interest rate into its equivalent multiplier
    // (for purposes of calculating total interest), divide it by INTEREST_RATE_SCALING_FACTOR_PERCENT -- e.g.
    //     10,000 => 0.01 interest multiplier
    uint256 public constant INTEREST_RATE_SCALING_FACTOR_MULTIPLIER = INTEREST_RATE_SCALING_FACTOR_PERCENT * 100;


    enum AmortizationUnitType {
        MINUTES, // 0 - since 1.0.13
        HOURS, // 1
        DAYS, // 2
        WEEKS, // 3
        MONTHS, // 4
        YEARS // 5
    }

    struct InterestParams {
        uint256 principalAmount;
        uint256 termStartUnixTimestamp;
        uint256 termEndUnixTimestamp;
        AmortizationUnitType amortizationUnitType;
        uint256 termLengthInAmortizationUnits;
        // interest rates can, at a maximum, have 4 decimal places of precision.
        uint256 interestRate;
    }

    modifier onlyRouter(LoanTypes loanType) {
        require(
            msg.sender == address(registry.getInventoryLoanRepaymentRouter()),
            "Only for Repayment Router."
        );
        _;
    }

    function initialize(Registry _registry) public initializer {
        __Pausable_init_unchained();
        __Ownable_init_unchained();
        registry = _registry;
    }

    modifier onlyDebtKernel() {
        require(
            msg.sender == address(registry.getInventoryLoanKernel()),
            'Only for Debt Kernel.'
        );
        _;
    }

    function collateralize(
        bytes32 agreementId, address[2]
        memory addresses // 0. Debtor, 1. assetHolder
    )
        private
    {
        return registry.getInventoryCollateralizer().collateralizeERC1155(agreementId, addresses[0], addresses[1]);
    }

    /**
    *   Start terms contract and sieze collateral tokens
    */

    function registerTermStart(bytes32 agreementId, address[2] memory addresses) // 0. Debtor, 1. assetHolder
        public
        returns (bool _success)
    {
        address termsContract;
        bytes32 termsContractParameters;
        bytes16 collateralInfoParameters;

        (
            termsContract,
            termsContractParameters,
            collateralInfoParameters
        ) = registry.getInventoryLoanRegistry()
            .getTerms(agreementId);
        address principalTokenAddress = registry.getInventoryLoanRegistry().getAgreement(agreementId).principalTokenAddress;

        uint256 principalAmount = termsContractParameters.unpackPrincipalAmount();
        uint256 interestRate = termsContractParameters.unpackInterestRate();
        uint256 amortizationUnitType= termsContractParameters.unpackAmortizationUnitType();
        uint256 termLengthInAmortizationUnits= termsContractParameters.unpackTermLengthInAmortizationUnits();
        uint256 gracePeriodInDays= termsContractParameters.unpackGracePeriodInDays();

        collateralize(agreementId, addresses);

        // Returns true (i.e. valid) if the specified principal token is valid,
        // the specified amortization unit type is valid, and the terms contract
        // associated with the agreement is this one.  We need not check
        // if any of the other simple interest parameters are valid, because
        // it is impossible to encode invalid values for them.
        if (
            principalTokenAddress != address(0) &&
            amortizationUnitType < NUM_AMORTIZATION_UNIT_TYPES &&
            termsContract == address(this)
        ) {
            return true;
        }

        return false;
    }

    /**
   *   Get parameters by Agreement ID (commitment hash)
   */
    function _getAmortizationUnitLengthInSeconds(AmortizationUnitType amortizationUnitType)
    internal
    pure
    returns (uint)
    {
        if (amortizationUnitType == AmortizationUnitType.MINUTES) {
            return MINUTE_LENGTH_IN_SECONDS;
        } else if (amortizationUnitType == AmortizationUnitType.HOURS) {
            return HOUR_LENGTH_IN_SECONDS;
        } else if (amortizationUnitType == AmortizationUnitType.DAYS) {
            return DAY_LENGTH_IN_SECONDS;
        } else if (amortizationUnitType == AmortizationUnitType.WEEKS) {
            return WEEK_LENGTH_IN_SECONDS;
        } else if (amortizationUnitType == AmortizationUnitType.MONTHS) {
            return MONTH_LENGTH_IN_SECONDS;
        } else if (amortizationUnitType == AmortizationUnitType.YEARS) {
            return YEAR_LENGTH_IN_SECONDS;
        } else {
            revert("Unknown amortization unit type.");
        }
    }

    function _unpackParamsForAgreementID(
        LoanTypes loanType,
        bytes32 agreementId
    )
    internal
    view
    returns (InterestParams memory params)
    {
        bytes32 parameters;
        uint issuanceBlockTimestamp = 0;
        address principalTokenAddress;
        if (loanType == LoanTypes.WAREHOUSE_RECEIPT) {
/*
            CommodityDebtRegistry commodityDebtRegistry = CommodityDebtRegistry(contractRegistry.get(COMMODITY_DEBT_REGISTRY));
            parameters = commodityDebtRegistry.getTermsContractParameters(agreementId);
            issuanceBlockTimestamp = commodityDebtRegistry.getIssuanceBlockTimestamp(agreementId);
*/
        } else if (loanType == LoanTypes.INVENTORY_FINANCE) {
            InventoryLoanRegistry inventoryLoanDebtRegistry = registry.getInventoryLoanRegistry();
            parameters = inventoryLoanDebtRegistry.getTermsContractParameters(agreementId);
            issuanceBlockTimestamp = inventoryLoanDebtRegistry.getIssuanceBlockTimestamp(agreementId);
            principalTokenAddress = inventoryLoanDebtRegistry.getAgreement(agreementId).principalTokenAddress;
        } else {
/*
            InvoiceDebtRegistry invoiceDebtRegistry = InvoiceDebtRegistry(contractRegistry.get(INVOICE_DEBT_REGISTRY));
            issuanceBlockTimestamp = invoiceDebtRegistry.getIssuanceBlockTimestamp(agreementId);
            parameters = invoiceDebtRegistry.getTermsContractParameters(agreementId);
*/
        }

        // The principal amount denominated in the aforementioned token.
        uint256 principalAmount = parameters.unpackPrincipalAmount();
        uint256 interestRate = parameters.unpackInterestRate();
        // The amortization unit in which the repayments installments schedule is defined.
        uint256 rawAmortizationUnitType= parameters.unpackAmortizationUnitType();
        // The debt's entire term's length, denominated in the aforementioned amortization units
        uint256 termLengthInAmortizationUnits= parameters.unpackTermLengthInAmortizationUnits();
        uint256 gracePeriodInDays= parameters.unpackGracePeriodInDays();

        // Ensure that the encoded principal token address is valid
        require(principalTokenAddress != address(0), "Invalid principal token address.");

        // Before we cast to `AmortizationUnitType`, ensure that the raw value being stored is valid.
        require(
            rawAmortizationUnitType <= uint(AmortizationUnitType.YEARS),
            "Amortization Unit Type is invalid."
        );

        AmortizationUnitType amortizationUnitType = AmortizationUnitType(rawAmortizationUnitType);

        // Calculate term length base on Amortization Unit and number
        uint termLengthInSeconds = termLengthInAmortizationUnits.mul(
            _getAmortizationUnitLengthInSeconds(amortizationUnitType)
        );

        return InterestParams({
            principalAmount: principalAmount,
            interestRate: interestRate,
            termStartUnixTimestamp: issuanceBlockTimestamp,
            termEndUnixTimestamp: termLengthInSeconds.add(issuanceBlockTimestamp),
            amortizationUnitType: amortizationUnitType,
            termLengthInAmortizationUnits: termLengthInAmortizationUnits
        });
    }


    /// When called, the registerRepayment function records the debtor's
    ///  repayment, as well as any auxiliary metadata needed by the contract
    ///  to determine ex post facto the value repaid (e.g. current USD
    ///  exchange rate)
    /// @param  agreementId bytes32. The agreement id (issuance hash) of the debt agreement to which this pertains.
    /// @param  unitsOfRepayment uint. The units-of-value repaid in the transaction.
    /// @param  tokenAddress address. The address of the token with which the repayment transaction was executed.
    function registerRepayment(
        bytes32 agreementId,
        uint256 unitsOfRepayment,
        address tokenAddress
    ) public onlyRouter(LoanTypes.INVENTORY_FINANCE) returns (uint256 remains) {
        InventoryLoanRegistry debtRegistry = registry.getInventoryLoanRegistry();
        require(
            tokenAddress == debtRegistry.getAgreement(agreementId).principalTokenAddress,
            'LoanTermsContract: Invalid token for repayment.'
        );

        // solium-disable-next-line
        uint256 currentTimestamp = block.timestamp;

        uint256 expectedPrincipal;
        uint256 expectedInterest;
        // query total outstanding amounts
        (expectedPrincipal, expectedInterest) = getExpectedRepaymentValues(
            agreementId,
            currentTimestamp
        );
        // TODO: Currently only allow Debtor to repay with amount >= expectedInterest of that time
        // Because, we haven't made any mechanism to manage outstanding interest amounts in the case when Debtor
        // repaid with amount < expectedInterest (at that moment)
        require(
            unitsOfRepayment >= expectedInterest,
            'LoanTermsContract: Expected interest amount is minimum.'
        );

        // exceed expectation, Debtor can pay all at once
        if (unitsOfRepayment >= expectedPrincipal.add(expectedInterest)) {
            debtRegistry.setCompletedRepayment(agreementId);
            debtRegistry.addRepaidInterestAmount(agreementId, expectedInterest);
            debtRegistry.addRepaidPrincipalAmount(
                agreementId,
                expectedPrincipal
            );
            // put the remain to interest
            remains = unitsOfRepayment.sub(
                expectedPrincipal.add(expectedInterest)
            );
        } else {
            // if currently Debtor no need to repay for interest
            if (expectedInterest == 0) {
                if (unitsOfRepayment >= expectedPrincipal) {
                    debtRegistry.addRepaidPrincipalAmount(
                        agreementId,
                        expectedPrincipal
                    );
                    // with the remains
                    if (unitsOfRepayment.sub(expectedPrincipal) > 0) {
                        debtRegistry.addRepaidInterestAmount(
                            agreementId,
                            unitsOfRepayment.sub(expectedPrincipal)
                        );
                    }
                } else {
                    debtRegistry.addRepaidPrincipalAmount(
                        agreementId,
                        unitsOfRepayment
                    );
                }
            } else {
                // if expectedInterest > 0 ( & unitsOfRepayment >= expectedInterest)
                debtRegistry.addRepaidInterestAmount(
                    agreementId,
                    expectedInterest
                );
                if (unitsOfRepayment.sub(expectedInterest) > 0) {
                    // Debtor is not able to fulfill the expectedPrincipal as we already validated from first IF statement
                    // -> there is no remains for adding to repaidInterestAmount
                    debtRegistry.addRepaidPrincipalAmount(
                        agreementId,
                        unitsOfRepayment.sub(expectedInterest)
                    );
                }
            }
        }

        // Update Debt registry record
        debtRegistry.updateLastRepaymentTimestamp(
            agreementId,
            currentTimestamp
        );
        debtRegistry.selfEvaluateCollateralRatio(agreementId);

        return remains;
    }
    function _validateNewInventoryCollateralParamsSecureLoan(
        bytes16 _oldCollateralParams,
        bytes16 _newCollateralParams,
        uint _additionAmount
    ) internal pure returns (bool) {
        bool isCollateralTokenIdCorrect = _oldCollateralParams.unpackCollateralTokenId()
        == _newCollateralParams.unpackCollateralTokenId();

        bool isValidAmount = _newCollateralParams.unpackCollateralAmount()
        .sub(_oldCollateralParams.unpackCollateralAmount()) == _additionAmount;

        return (
            isCollateralTokenIdCorrect &&
            isValidAmount
        );

    }

    /**
        * Function will be called by Debt Kernel, supports Debtor to deposit more collateral
        */
    function registerSecureLoanWithCollateral(
        bytes32 agreementId,
        address debtor,
        uint256 additionAmount,
        address collateral,
        bytes16 collateralInfoParameters
    ) public {
        // query current terms contract parameters
        bytes16 currentTermsParameters;
        InventoryLoanRegistry debtRegistry = registry.getInventoryLoanRegistry();

        (, , currentTermsParameters) = debtRegistry.getTerms(agreementId);

        // validate new paramters, compare the amounts
        require(
            _validateNewInventoryCollateralParamsSecureLoan(
                currentTermsParameters,
                collateralInfoParameters,
                additionAmount
            ),
            'Terms Contract: Invalid collateral information parameters.'
        );

        // Sezie collateral tokens with addition amount
        registry.getInventoryCollateralizer()
            .additionInventoryCollateralize(
                agreementId,
                debtor,
                additionAmount,
                collateral
            );

        // update terms contract parameters, then re evaluate CR
        debtRegistry.updateCollateralInfoParameters(
            agreementId,
            collateralInfoParameters
        );
        debtRegistry.selfEvaluateCollateralRatio(agreementId);
    }

    /**
    * Function will be called by Debt Kernel, supports Debtor to deposit more collateral
    */
    function registerInsecureLoanByWithdrawCollateral(
        bytes32 agreementId,
        address debtor,
        uint256 withdrawAmount,
        address collateral,
        bytes16 collateralInfoParameters
    ) public {
        InventoryLoanRegistry debtRegistry = registry.getInventoryLoanRegistry();
        address debtorOfAgreement = debtRegistry.getDebtor(agreementId);
        require(debtor == debtorOfAgreement, 'Invalid debtor of agreement');

        uint256 newCollateralAmount = _validateNewCollateralAmount(
            agreementId,
            collateralInfoParameters,
            withdrawAmount,
            debtRegistry
        );
        // Calculate CR after sell collateral by invoice
        require(
            _validateNewCollateralRatioWithInvoice(
                0,
                agreementId,
                newCollateralAmount,
                debtRegistry
            ),
            'InventoryInterest: Invalid collateral ratio, bellow min collateral ratio'
        );

        // Sezie collateral tokens with addition amount
        registry.getInventoryCollateralizer()
            .withdrawInventoryCollateralize(
            agreementId,
            debtor,
            withdrawAmount,
            collateral
        );

        // update terms contract parameters, then re evaluate CR
        debtRegistry.updateCollateralInfoParameters(
            agreementId,
            collateralInfoParameters
        );
        debtRegistry.selfEvaluateCollateralRatio(agreementId);
    }

    /**
    * Function will be called by Debt Kernel, supports Debtor to sell collateral
    */
    function registerSellCollateral(
        bytes32 agreementId,
        uint256 amountCollateral,
        uint256 price,
        uint256 fiatTokenIndex,
        address collateral,
        bytes16 collateralInfoParameters
    ) public {
        // TODO tanlm Temporary. Fix this
        address fiatTokenAddress = address(0);
        require(
            fiatTokenAddress != address(0),
            'Token address must different with NULL.'
        );
        require(amountCollateral > 0, 'Amount must greater than 0.');
        require(price > 0, 'Price must greater than 0.');

        InventoryLoanRegistry debtRegistry = registry.getInventoryLoanRegistry();

        uint256 _amount = _computePriceValue(amountCollateral, price);
        _validateNewCollateralAmount(
            agreementId,
            collateralInfoParameters,
            amountCollateral,
            debtRegistry
        );

        bytes32 sellId = _getSellCollateralId(
            agreementId,
            _amount,
            fiatTokenIndex
        );
        debtRegistry.setWaitingSellCollateral(
            agreementId,
            sellId,
            _amount,
            fiatTokenIndex
        );

        //Burn collateral
        _burnCollateralAndUpdateInfo(
            agreementId,
            amountCollateral,
            collateral,
            collateralInfoParameters,
            debtRegistry
        );
    }

    /**
    * Function will be called by Debt Kernel, supports Buyer to pay for collateral by fiat
    */
    function registerPayCollateralByFiat(
        bytes32 agreementId,
        bytes32 sellCollateralId,
        address payer
    ) public {
        InventoryLoanRegistry debtRegistry = registry.getInventoryLoanRegistry();
        require(
            debtRegistry.isWaitingSellCollateralExisted(
                agreementId,
                sellCollateralId
            ),
            'InventoryInterestTermsContract: Sell info not existed'
        );
        (uint256 _amount, uint256 fiatTokenIndex) = debtRegistry
            .getWaitingSellCollateral(agreementId, sellCollateralId);

        // TODO tanlm: temporary. Fix this
        address fiatTokenAddress = address(0);
        require(
            fiatTokenAddress != address(0),
            'Token address must different with NULL.'
        );

        if (debtRegistry.liquidatedLoan(agreementId)) {
            // Repay fully to loan
            registry.getInventoryLoanRepaymentRouter()
                ._doRepay(agreementId, payer, _amount, fiatTokenAddress);
            _amount = 0;

        } else {
            (, uint256 collateralAmount) = debtRegistry
                .getCollateralInfoParameters(agreementId);
            uint256 currentInvoiceAmount = debtRegistry._getTotalInvoiceAmount(
                agreementId
            );
            uint256 minCollateralRatio = debtRegistry.getMinCollateralRatio(
                agreementId
            );
            // Calculate CR after sell collateral. If CR bellow min CR, must repay for the loan to make it equal min CR
            _amount = _repayLoanIfNeed(
                _amount,
                agreementId,
                collateralAmount,
                currentInvoiceAmount,
                [payer, fiatTokenAddress],
                minCollateralRatio
            );
        }

        debtRegistry.selfEvaluateCollateralRatio(agreementId);

        //Transfer fiat from payer to trader
        if (_amount > 0) {
            address debtor = debtRegistry.getDebtor(agreementId);
            require(
                    IERC20(fiatTokenAddress)
                    .transferFrom(payer, debtor, _amount),
                'Unsuccessfully transferred remains amount to Debtor.'
            );
        }
    }

    /**
    * Function will be called by Debt Kernel, supports Buyer to pay for collateral by invoice
    */
    function registerPayCollateralByInvoice(
        bytes32 agreementId,
        bytes32 sellCollateralId,
        address payer,
        uint256 dueDate,
        uint256 salt
    ) public returns (uint256) {
        InventoryLoanRegistry debtRegistry = registry.getInventoryLoanRegistry();
        require(
            debtRegistry.isWaitingSellCollateralExisted(
                agreementId,
                sellCollateralId
            ),
            'InventoryInterestTermsContract: Sell info not existed'
        );
        (uint256 _amount, uint256 fiatTokenIndex) = debtRegistry
            .getWaitingSellCollateral(agreementId, sellCollateralId);

        //Create AIT to trader and financed to inventory loan
        uint256 invoiceTokenId = _createAITFinanced(
            agreementId,
            payer,
            _amount,
            fiatTokenIndex,
            dueDate,
            salt,
            debtRegistry
        );
        debtRegistry.selfEvaluateCollateralRatio(agreementId);

        return invoiceTokenId;
    }

    /**
    Calculate CR after invoice payment and repay to loan if CR bellow min CR
    */
    function registerPayFromInvoice(
        bytes32 agreementId,
        uint256 invoiceId,
        address fiatTokenAddress,
        address payer
    ) public returns (uint256 remainAmount) {
        uint256 invoiceAmount = registry.getAcceptedInvoiceToken()
            .getFiatAmount(invoiceId);
        InventoryLoanRegistry debtRegistry = registry.getInventoryLoanRegistry();

        uint256 currentInvoiceAmount = debtRegistry._getTotalInvoiceAmount(
            agreementId
        );

        // query current terms contract parameters
        bytes16 currentCollateralInfoParameters;
        (, , currentCollateralInfoParameters) = debtRegistry.getTerms(
            agreementId
        );

        uint256 currentCollateralAmount = currentCollateralInfoParameters.unpackCollateralAmount();

        if (debtRegistry.liquidatedLoan(agreementId)) {
            // Repay fully to loan
            registry.getInventoryLoanRepaymentRouter()
                ._doRepay(agreementId, payer, invoiceAmount, fiatTokenAddress);
            remainAmount = 0;

        } else {
            uint256 minCollateralRatio = debtRegistry.getMinCollateralRatio(
                agreementId
            );
            // Calculate CR after pay invoice. If CR bellow min CR, must repay for the loan to make it equal min CR
            remainAmount = _repayLoanIfNeed(
                invoiceAmount,
                agreementId,
                currentCollateralAmount,
                currentInvoiceAmount - invoiceAmount,
                [payer, fiatTokenAddress],
                minCollateralRatio
            );
        }

        //Remove invoice relate to loan
        debtRegistry.removeInvoiceId(agreementId, invoiceId);
    }

    function _validateNewInventoryTermsContractParamsDrawdown(
        bytes32 _oldTermsContractParameters,
        bytes32 _newTermsContractParameters,
        uint _drawdownAmount
    ) internal pure returns (bool) {
        bool isValidPrincipalAmount = _newTermsContractParameters.unpackPrincipalAmount()
        .sub(_oldTermsContractParameters.unpackPrincipalAmount()) == _drawdownAmount;

        bool isInterestRateCorrect = _oldTermsContractParameters.unpackInterestRate()
        == _newTermsContractParameters.unpackInterestRate();

        bool isAmortizationUnitTypeCorrect = _oldTermsContractParameters.unpackAmortizationUnitType()
        == _newTermsContractParameters.unpackAmortizationUnitType();

        bool isTermLengthInAmortizationUnitsCorrect = _oldTermsContractParameters.unpackTermLengthInAmortizationUnits()
        == _newTermsContractParameters.unpackTermLengthInAmortizationUnits();

        bool isGracePeriodInDaysCorrect = _oldTermsContractParameters.unpackGracePeriodInDays()
        == _newTermsContractParameters.unpackGracePeriodInDays();

        return (
            isValidPrincipalAmount &&
            isInterestRateCorrect &&
            isAmortizationUnitTypeCorrect &&
            isTermLengthInAmortizationUnitsCorrect &&
            isGracePeriodInDaysCorrect
        );

    }

    /**
    * Function will be called by Debt Kernel, supports Debtor to deposit more collateral
    */
    function registerDrawdownLoan(
        bytes32 agreementId,
        uint256 drawdownAmount,
        bytes32 termsContractParameters
    ) public {
        // query current terms contract parameters
        InventoryLoanRegistry debtRegistry = registry.getInventoryLoanRegistry();
        require(
            drawdownAmount > 0,
            'Inventory Terms Contract: Drawdown amount must greater than 0.'
        );

        (, bytes32 currentTermsParameters, ) = debtRegistry.getTerms(
            agreementId
        );
        // validate new paramters, compare the amounts
        require(
            _validateNewInventoryTermsContractParamsDrawdown(
                currentTermsParameters,
                termsContractParameters,
                drawdownAmount
            ),
            'Inventory Terms Contract: Invalid terms contract parameters.'
        );
        require(
            _validateNewCollateralRatioWhenDrawdown(
                agreementId,
                drawdownAmount,
                debtRegistry
            ),
            'InventoryInterest: Invalid collateral ratio, bellow min collateral ratio'
        );

        // update terms contract parameters, then re evaluate CR
        debtRegistry.updateLoanTermParameters(
            agreementId,
            termsContractParameters
        );
        debtRegistry.selfEvaluateCollateralRatio(agreementId);

    }

    function _validateNewInventoryCollateralParamsSellCollateral(
        bytes16 _oldCollateralParams,
        bytes16 _newCollateralParams,
        uint _sellAmount
    ) internal pure returns (bool) {
        bool isCollateralTokenIdCorrect = _oldCollateralParams & 0xffffffff000000000000000000000000
        == _newCollateralParams & 0xffffffff000000000000000000000000;

        bool isValidAmount = uint256(uint128(_oldCollateralParams) & 0x00000000ffffffffffffffffffffffff)
        .sub(uint256(uint128(_newCollateralParams) & 0x00000000ffffffffffffffffffffffff)) == _sellAmount;

        return (
        isCollateralTokenIdCorrect &&
        isValidAmount
        );

    }

    // helper for sellCollateral
    function _validateNewCollateralAmount(
        bytes32 agreementId,
        bytes16 collateralInfoParameters,
        uint256 amountCollateral,
        InventoryLoanRegistry debtRegistry
    ) private view returns (uint256 newCollateralAmount) {
        // query current terms contract parameters
        bytes16 currentCollateralInfoParameters;
        (, , currentCollateralInfoParameters) = debtRegistry.getTerms(
            agreementId
        );

        // validate new paramters, compare the amounts
        require(
            _validateNewInventoryCollateralParamsSellCollateral(
                currentCollateralInfoParameters,
                collateralInfoParameters,
                amountCollateral
            ),
            'Inventory Terms Contract: Invalid collateral information parameters.'
        );

        newCollateralAmount = collateralInfoParameters.unpackCollateralAmount();
    }

    /**
    *
    */
    function registerForeclosureLoan(bytes32 agreementId)
        public
    {
        InventoryLoanRegistry inventoryLoanDebtRegistry = registry.getInventoryLoanRegistry();
        require(
            !inventoryLoanDebtRegistry.completedLoans(agreementId),
            'InventoryInterestTermsContract: Unable to foreclosure loan when Loan terms is fulfilled.'
        );
        require(
            inventoryLoanDebtRegistry.isExpiredOrReadyForLiquidation(
                agreementId
            ),
            'InventoryInterestTermsContract: Still not meet the requirements to foreclosure.'
        );

        inventoryLoanDebtRegistry.setLoanLiquidated(agreementId);
    }

    function _validateNewCollateralRatioWithInvoice(
        uint256 _amountSold,
        bytes32 agreementId,
        uint256 newCollateralAmount,
        InventoryLoanRegistry inventoryLoanDebtRegistry
    ) private view returns (bool) {
        uint256 currentInvoiceAmount = inventoryLoanDebtRegistry
            ._getTotalInvoiceAmount(agreementId);
        (uint256 cr, , ) = _computeExpectedCR(
            agreementId,
            newCollateralAmount,
            currentInvoiceAmount + _amountSold,
            0
        );
        uint256 minCollateralRatio = inventoryLoanDebtRegistry
            .getMinCollateralRatio(agreementId);

        if (cr < minCollateralRatio) {
            return false;
        }

        return true;
    }

    function _validateNewCollateralRatioWhenDrawdown(
        bytes32 agreementId,
        uint256 _amountDrawdown,
        InventoryLoanRegistry inventoryLoanDebtRegistry
    ) private view returns (bool) {
        uint256 currentInvoiceAmount = inventoryLoanDebtRegistry
            ._getTotalInvoiceAmount(agreementId);
        (, uint256 collateralAmount) = inventoryLoanDebtRegistry
            .getCollateralInfoParameters(agreementId);

        (uint256 cr, , ) = _computeExpectedCR(
            agreementId,
            collateralAmount,
            currentInvoiceAmount,
            _amountDrawdown
        );
        uint256 minCollateralRatio = inventoryLoanDebtRegistry
            .getMinCollateralRatio(agreementId);

        if (cr < minCollateralRatio) {
            return false;
        }

        return true;
    }

    // Calculate CR after sell collateral. If CR bellow min CR, must repay for the loan to make it equal min CR
    function _repayLoanIfNeed(
        uint256 _amountSold,
        bytes32 agreementId,
        uint256 newCollateralAmount,
        uint256 invoiceValue,
        address[2] memory payerInfo, //1-payer, 2-fiatTokenAddress
        uint256 minCollateralRatio
    ) private returns (uint256) {
        (uint256 cr, uint256 lastPrice, uint256 totalRemain) = _computeExpectedCR(
            agreementId,
            newCollateralAmount,
            invoiceValue,
            0
        );

        if (cr < minCollateralRatio) {
            // repay loan until CR = min CR
            uint256 principalValueToSatisfyMinCR = _computePrincipalValueRequire(
                newCollateralAmount,
                lastPrice,
                invoiceValue,
                minCollateralRatio
            );
            uint256 repayValueToSatisfyMinCR;

            if (principalValueToSatisfyMinCR == 0) {
                repayValueToSatisfyMinCR = totalRemain;
            } else {
                repayValueToSatisfyMinCR =
                    totalRemain -
                    principalValueToSatisfyMinCR;
            }

            if (repayValueToSatisfyMinCR > _amountSold) {
                registry.getInventoryLoanRepaymentRouter()
                    ._doRepay(
                    agreementId,
                    payerInfo[0],
                    _amountSold,
                    payerInfo[1]
                );
                _amountSold = 0;

            } else {
                registry.getInventoryLoanRepaymentRouter()
                    ._doRepay(
                    agreementId,
                    payerInfo[0],
                    repayValueToSatisfyMinCR,
                    payerInfo[1]
                );
                _amountSold = _amountSold.sub(repayValueToSatisfyMinCR);
            }
        }

        return _amountSold;
    }

    // Calculate CR after sell collateral
    function _computeExpectedCR(
        bytes32 agreementId,
        uint256 newCollateralAmount,
        uint256 invoiceAmount,
        uint256 drawdownAmount
    )
        private
        view
        returns (uint256 cr, uint256 lastPrice, uint256 totalRemain)
    {
        lastPrice = registry.getInventoryLoanRegistry()
            .getCollateralLastPrice(agreementId);

        uint256 currentTimestamp = block.timestamp;
        totalRemain = getTotalExpectedRepaymentValue(
            agreementId,
            currentTimestamp
        );

        cr = _computeCR(
            newCollateralAmount,
            lastPrice,
            invoiceAmount,
            totalRemain + drawdownAmount
        );
    }

    function _burnCollateralAndUpdateInfo(
        bytes32 agreementId,
        uint256 amountCollateral,
        address collateral,
        bytes16 collateralInfoParameters,
        InventoryLoanRegistry debtRegistry
    ) private {
        registry.getInventoryCollateralizer()
            .burnInventoryCollateralize(
            agreementId,
            amountCollateral,
            collateral
        );

        // update terms contract parameters, then re evaluate CR
        debtRegistry.updateCollateralInfoParameters(
            agreementId,
            collateralInfoParameters
        );
        debtRegistry.selfEvaluateCollateralRatio(agreementId);
    }

    function _createAITFinanced(
        bytes32 agreementId,
        address payer,
        uint256 _amount,
        uint256 fiatTokenIndex,
        uint256 dueDate,
        uint256 salt,
        InventoryLoanRegistry debtRegistry
    ) private returns (uint256 invoiceTokenId) {
        AcceptedInvoiceToken ait = registry.getAcceptedInvoiceToken();

        // TODO tanlm Temporary disable
//        invoiceTokenId = ait.mint(
//            [payer, address(registry.getInventoryCollateralizer())],
//            _amount,
//            fiatTokenIndex,
//            dueDate,
//            false,
//            salt
//        );
//        invoiceTokenId = 0;
/*
        ait.beginInventoryFinancing(invoiceTokenId, agreementId);
        ait.modifyBeneficiary(
            invoiceTokenId,
            debtRegistry.getDebtor(agreementId)
        );
*/
        debtRegistry.insertInvoiceFinancedToInventoryLoan(
            agreementId,
            invoiceTokenId
        );
    }

    /**
     * Helper function for computing the hash of a given issuance,
     * and, in turn, its agreementId
     */
    function _getSellCollateralId(
        bytes32 agreementId,
        uint256 amountPayment,
        uint256 fiatTokenIndex
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(agreementId, amountPayment, fiatTokenIndex)
            );
    }

    /**
    *
    */
    function getTermEndTimestamp(bytes32 _agreementId)
        public
        view
        returns (uint256)
    {
        InterestParams memory params = _unpackParamsForAgreementID(
            LoanTypes.INVENTORY_FINANCE,
            _agreementId
        );
        return params.termEndUnixTimestamp;
    }

    /**
    * Term will be completed if participants met all of conditions
    */
    function registerConcludeTerm(bytes32 agreementId) public {
        // validate repayment status
        InventoryLoanRegistry debtRegistry = registry.getInventoryLoanRegistry();
        require(
            debtRegistry.completedRepayment(agreementId),
            'Debtor has not completed repayment yet.'
        );
        registry.getInventoryCollateralizer()
            .returnInventoryCollateral(agreementId);
        if (debtRegistry.liquidatedLoan(agreementId)) {
            debtRegistry.removeLiquidatedLoan(agreementId);
        }

        debtRegistry.setCompletedLoan(agreementId);
    }

    /**
    * Expected repayment value with Amortization of Interest and Principal
    * (AMORTIZATION) - will be used for repayment from Debtor
    */
    function getExpectedRepaymentValues(bytes32 agreementId, uint256 timestamp)
        public
        view
        returns (uint256 expectedPrincipal, uint256 expectedInterest)
    {
        InterestParams memory params = _unpackParamsForAgreementID(
            LoanTypes.INVENTORY_FINANCE,
            agreementId
        );
        InventoryLoanRegistry debtRegistry = registry.getInventoryLoanRegistry();

        uint256 repaidPrincipalAmount = debtRegistry.getRepaidPrincipalAmount(
            agreementId
        );
        uint256 repaidInterestAmount = debtRegistry.getRepaidInterestAmount(
            agreementId
        );
        uint256 lastRepaymentTimestamp = debtRegistry.getLastRepaymentTimestamp(
            agreementId
        );

        bool isManualInterestLoan = debtRegistry.manualInterestLoan(agreementId);
        uint256 manualInterestAmountLoan;
        if (isManualInterestLoan) {
            manualInterestAmountLoan = debtRegistry.getManualInterestAmountLoan(
                agreementId
            );
        }

        (
            expectedPrincipal,
            expectedInterest
        ) = _getExpectedRepaymentValuesToTimestamp(
            params,
            lastRepaymentTimestamp,
            timestamp,
            repaidPrincipalAmount,
            repaidInterestAmount,
            isManualInterestLoan,
            manualInterestAmountLoan
        );
    }

    // Calculate interest amount for a duration with specific Principal amount
    function _calculateInterestForDuration(
        uint _principalAmount,
        uint _interestRate,
        uint _durationLengthInSec
    ) internal pure returns (uint) {
        return _principalAmount.mul(_interestRate).mul(_durationLengthInSec.div(DAY_LENGTH_IN_SECONDS))
        .div(INTEREST_RATE_SCALING_FACTOR_MULTIPLIER).div(YEAR_LENGTH_IN_DAYS);
    }

    function getStartDateInTimestamp(uint _timestamp) private pure returns (uint) {
        uint secondInDay = _timestamp.mod(DAY_LENGTH_IN_SECONDS);
        return  _timestamp.sub(secondInDay);
    }
    // Calculate interest amount Debtor need to pay until current date
    function _calculateInterestAmountToTimestamp(
        uint _principalAmount,
        uint _currentPrincipalAmount,
        uint _paidInterestAmount,
        uint _annualInterestRate,
        uint _startTermTimestamp,
        uint _endTermTimestamp,
        uint _lastRepayTimestamp,
        uint _timestamp
    ) internal pure returns (uint) {
        if (_timestamp <= _startTermTimestamp) {
            return 0;
        }
        uint interest = 0;

        uint startOfDayOfLastRepay = getStartDateInTimestamp(_lastRepayTimestamp);
        uint startOfDayOfTermsStart = getStartDateInTimestamp(_startTermTimestamp);
        uint startOfDayToCalculateInterest = getStartDateInTimestamp(_timestamp);

        uint elapseTimeFromLastRepay = startOfDayToCalculateInterest.sub(startOfDayOfLastRepay);
        uint elapseTimeFromStart = startOfDayToCalculateInterest.sub(startOfDayOfTermsStart).add(DAY_LENGTH_IN_SECONDS);

        // If still within the term length
        if (_timestamp < _endTermTimestamp) {
            // Have just made new repayment
            if (elapseTimeFromLastRepay == 0 && _paidInterestAmount > 0) {
                interest = 0;
            } else {
                if (_paidInterestAmount > 0) {
                    // Has made at least 1 repayment
                    interest = _calculateInterestForDuration(
                        _currentPrincipalAmount,
                        _annualInterestRate,
                        elapseTimeFromLastRepay
                    );
                } else {
                    // Haven't made any repayment
                    interest = _calculateInterestForDuration(
                        _principalAmount,
                        _annualInterestRate,
                        elapseTimeFromStart
                    );
                }
            }

        } else if (_timestamp >= _endTermTimestamp) {
            // If debtor has made at least 1 repayment
            if (_paidInterestAmount > 0) {
                interest = _calculateInterestForDuration(
                    _currentPrincipalAmount,
                    _annualInterestRate,
                    elapseTimeFromLastRepay
                );
            } else {
                interest = _calculateInterestForDuration(
                    _principalAmount,
                    _annualInterestRate,
                    elapseTimeFromStart
                );
            }
        } else {
            interest = 0;
        }
        return interest;
    }

    function _getExpectedRepaymentValuesToTimestamp(
        InterestParams memory _params,
        uint _lastRepaymentTimestamp, // timestamp of last repayment from debtor
        uint _timestamp,
        uint repaidPrincipalAmount,
        uint repaidInterestAmount,
        bool isManualInterestLoan,
        uint manualInterestAmountLoan
    ) internal pure returns (uint expectedPrinciapal, uint expectedInterest) {
        uint outstandingPrincipal = _params.principalAmount.sub(repaidPrincipalAmount);

        expectedPrinciapal = outstandingPrincipal;

        if (isManualInterestLoan) {
            expectedInterest = manualInterestAmountLoan;
        } else {
            expectedInterest = _calculateInterestAmountToTimestamp(
                _params.principalAmount,
                outstandingPrincipal,
                repaidInterestAmount,
                _params.interestRate,
                _params.termStartUnixTimestamp,
                _params.termEndUnixTimestamp,
                _lastRepaymentTimestamp,
                _timestamp
            );
        }
    }

    function getTermStartUnixTimestamp(bytes32 _agreementId)
        public
        view
        returns (uint256)
    {
        InterestParams memory params = _unpackParamsForAgreementID(
            LoanTypes.INVENTORY_FINANCE,
            _agreementId
        );
        return params.termStartUnixTimestamp;
    }

    /**
    * Get TOTAL expected repayment value at specific timestamp
    * (NO AMORTIZATION)
    */
    function getTotalExpectedRepaymentValue(
        bytes32 agreementId,
        uint256 timestamp
    )
        public
        view
        returns (uint256 expectedRepaymentValue)
    {
        uint256 principalAmount;
        uint256 interestAmount;
        (principalAmount, interestAmount) = getExpectedRepaymentValues(
            agreementId,
            timestamp
        );
        expectedRepaymentValue = principalAmount.add(interestAmount);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
}
