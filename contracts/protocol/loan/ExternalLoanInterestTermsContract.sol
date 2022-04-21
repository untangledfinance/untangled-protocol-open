pragma solidity ^0.8.0;

import './base/LoanTermsContractBase.sol';
import './ExternalLoanDebtRegistry.sol';
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract ExternalLoanInterestTermsContract is LoanTermsContractBase {
    using SafeMath for uint256;

    mapping(bytes32 => bool) startedLoan;

    mapping(bytes32 => uint256) public repaidPrincipalAmounts;
    mapping(bytes32 => uint256) public repaidInterestAmounts;

    mapping(bytes32 => bool) public completedRepayment;

    modifier onlyHaventStartedLoan(bytes32 agreementId) {
        require(!startedLoan[agreementId], 'LOAN1');
        _;
    }

    modifier onlyStartedLoan(bytes32 agreementId) {
        require(startedLoan[agreementId], 'LOAN2');
        _;
    }

    function initialize(
        Registry _registry
    ) public override initializer {
        __LoanTermsContractBase_init(_registry);
    }

    //************************ */
    // INTERNAL
    //************************ */

    // Register to start Loan term for batch of agreement Ids
    function registerTermStart(bytes32 agreementId) public onlyHaventStartedLoan(agreementId) returns (bool) {
        startedLoan[agreementId] = true;
        return true;
    }

    function getRepaidPrincipalAmount(bytes32 agreementId) public view returns (uint256) {
        return repaidPrincipalAmounts[agreementId];
    }

    function addRepaidPrincipalAmount(bytes32 agreementId, uint256 repaidAmount) public {
        repaidPrincipalAmounts[agreementId] = repaidPrincipalAmounts[agreementId].add(repaidAmount);
    }

    function setRepaidPrincipalAmount(bytes32 agreementId, uint256 repaidAmount) public {
        repaidPrincipalAmounts[agreementId] = repaidAmount;
    }

    function addRepaidInterestAmount(bytes32 agreementId, uint256 repaidAmount) public {
        repaidInterestAmounts[agreementId] = repaidInterestAmounts[agreementId].add(repaidAmount);
    }

    function setRepaidInterestAmount(bytes32 agreementId, uint256 repaidAmount) public {
        repaidInterestAmounts[agreementId] = repaidAmount;
    }

    function getRepaidInterestAmount(bytes32 agreementId) public view returns (uint256) {
        return repaidInterestAmounts[agreementId];
    }

    function getValueRepaidToDate(bytes32 agreementId) public view returns (uint256, uint256) {
        return (repaidPrincipalAmounts[agreementId], repaidInterestAmounts[agreementId]);
    }

    function isCompletedRepayments(bytes32[] memory agreementIds) public view returns (bool[] memory) {
        bool[] memory result = new bool[](agreementIds.length);
        for (uint256 i = 0; i < agreementIds.length; i++) {
            result[i] = completedRepayment[agreementIds[i]];
        }
        return result;
    }

    function isCompletedRepayment(bytes32 agreementId) public view returns (bool) {
        return completedRepayment[agreementId];
    }

    function setCompletedRepayment(bytes32 agreementId) public {
        completedRepayment[agreementId] = true;
    }

    /**
     * Expected repayment value with Amortization of Interest and Principal
     * (AMORTIZATION) - will be used for repayment from Debtor
     */
    function getExpectedRepaymentValues(bytes32 agreementId, uint256 timestamp)
        public
        view
        onlyMappedToThisContract(LoanTypes.EXTERNAL, agreementId)
        returns (uint256 expectedPrincipal, uint256 expectedInterest)
    {
        InterestParams memory params = _unpackParamsForAgreementID(LoanTypes.EXTERNAL, agreementId);

        ExternalLoanDebtRegistry externalDebtRegistry = registry.getExternalLoanDebtRegistry();

        uint256 repaidPrincipalAmount = getRepaidPrincipalAmount(agreementId);
        uint256 repaidInterestAmount = getRepaidInterestAmount(agreementId);
        uint256 lastRepaymentTimestamp = externalDebtRegistry.getLastRepaymentTimestamp(agreementId);

        bool isManualInterestLoan = externalDebtRegistry.isManualInterestLoan(agreementId);
        uint256 manualInterestAmountLoan;
        if (isManualInterestLoan) {
            manualInterestAmountLoan = externalDebtRegistry.getManualInterestAmountLoan(agreementId);
        }

        (expectedPrincipal, expectedInterest) = _getExpectedRepaymentValuesToTimestamp(
            params,
            lastRepaymentTimestamp,
            timestamp,
            repaidPrincipalAmount,
            repaidInterestAmount,
            isManualInterestLoan,
            manualInterestAmountLoan
        );
    }

    function getMultiExpectedRepaymentValues(bytes32[] memory agreementIds, uint256 timestamp)
        public
        view
        returns (uint256[] memory, uint256[] memory)
    {
        uint256[] memory expectedPrincipals = new uint256[](agreementIds.length);
        uint256[] memory expectedInterests = new uint256[](agreementIds.length);
        for (uint256 i = 0; i < agreementIds.length; i++) {
            (uint256 expectedPrincipal, uint256 expectedInterest) = getExpectedRepaymentValues(
                agreementIds[i],
                timestamp
            );
            expectedPrincipals[i] = expectedPrincipal;
            expectedInterests[i] = expectedInterest;
        }
        return (expectedPrincipals, expectedInterests);
    }

    function isTermsContractExpired(bytes32 agreementId) public view returns (bool) {
        uint256 expTimestamp = registry.getExternalLoanDebtRegistry()
            .getExpirationTimestamp(agreementId);
        // solium-disable-next-line
        if (expTimestamp <= block.timestamp) {
            return true;
        }
        return false;
    }

    function registerConcludeLoan(bytes32 agreementId) external returns (bool) {
        ExternalLoanDebtRegistry externalDebtRegistry = registry.getExternalLoanDebtRegistry();
        require(isCompletedRepayment(agreementId), 'Debtor has not completed repayment yet.');

        externalDebtRegistry.setCompletedLoan(agreementId);

        emit LogRegisterCompleteTerm(agreementId);
        return true;
    }

    /**
     * Get TOTAL expected repayment value at specific timestamp
     * (NO AMORTIZATION)
     */
    function getTotalExpectedRepaymentValue(bytes32 agreementId, uint256 timestamp)
        public
        view
        onlyMappedToThisContract(LoanTypes.EXTERNAL, agreementId)
        returns (uint256 expectedRepaymentValue)
    {
        uint256 principalAmount;
        uint256 interestAmount;
        (principalAmount, interestAmount) = getExpectedRepaymentValues(agreementId, timestamp);
        expectedRepaymentValue = principalAmount.add(interestAmount);
    }

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
    ) public onlyRouter(LoanTypes.EXTERNAL) returns (uint256 remains) {
        InterestParams memory params = _unpackParamsForAgreementID(LoanTypes.EXTERNAL, agreementId);
        require(tokenAddress == params.principalTokenAddress, 'LoanTermsContract: Invalid token for repayment.');

        ExternalLoanDebtRegistry externalDebtRegistry = registry.getExternalLoanDebtRegistry();
        // solium-disable-next-line
        uint256 currentTimestamp = block.timestamp;

        uint256 expectedPrincipal;
        uint256 expectedInterest;
        // query total outstanding amounts
        (expectedPrincipal, expectedInterest) = getExpectedRepaymentValues(agreementId, currentTimestamp);
        // TODO: Currently only allow Debtor to repay with amount >= expectedInterest of that time
        // Because, we haven't made any mechanism to manage outstanding interest amounts in the case when Debtor
        // repaid with amount < expectedInterest (at that moment)
        require(unitsOfRepayment >= expectedInterest, 'LoanTermsContract: Expected interest amount is minimum.');

        // exceed expectation, Debtor can pay all at once
        if (unitsOfRepayment >= expectedPrincipal.add(expectedInterest)) {
            setCompletedRepayment(agreementId);
            addRepaidInterestAmount(agreementId, expectedInterest);
            addRepaidPrincipalAmount(agreementId, expectedPrincipal);
            // put the remain to interest
            remains = unitsOfRepayment.sub(expectedPrincipal.add(expectedInterest));
        } else {
            // if currently Debtor no need to repay for interest
            if (expectedInterest == 0) {
                if (unitsOfRepayment >= expectedPrincipal) {
                    addRepaidPrincipalAmount(agreementId, expectedPrincipal);
                    // with the remains
                    remains = unitsOfRepayment.sub(expectedPrincipal);
                } else {
                    addRepaidPrincipalAmount(agreementId, unitsOfRepayment);
                }
            } else {
                // if expectedInterest > 0 ( & unitsOfRepayment >= expectedInterest)
                addRepaidInterestAmount(agreementId, expectedInterest);
                if (unitsOfRepayment.sub(expectedInterest) > 0) {
                    // Debtor is not able to fulfill the expectedPrincipal as we already validated from first IF statement
                    // -> there is no remains for adding to repaidInterestAmount
                    addRepaidPrincipalAmount(agreementId, unitsOfRepayment.sub(expectedInterest));
                }
            }
        }

        // Update Debt registry record
        externalDebtRegistry.updateLastRepaymentTimestamp(agreementId, currentTimestamp);
        // externalDebtRegistry.selfEvaluateCollateralRatio(agreementId);

        // Emit new event
        emit LogRegisterRepayment(agreementId, payer, beneficiary, unitsOfRepayment, tokenAddress);

        return remains;
    }

    function getInterestRate(bytes32 agreementId) public view returns (uint256) {
        return _unpackParamsForAgreementID(LoanTypes.EXTERNAL, agreementId).interestRate;
    }
}
