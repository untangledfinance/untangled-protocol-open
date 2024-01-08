// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {Registry} from '../../storage/Registry.sol';
import '../../tokens/ERC721/types.sol';

abstract contract ILoanKernel {
    Registry public registry;

    /****************** */
    // CONSTANTS
    /****************** */

    enum FillingAddressesIndex {
        SECURITIZATION_POOL,
        PRINCIPAL_TOKEN_ADDRESS,
        REPAYMENT_ROUTER
    }

    enum FillingNumbersIndex {
        CREDITOR_FEE,
        ASSET_PURPOSE
    }

    bytes32 public constant NULL_ISSUANCE_HASH = bytes32(0);
    bytes16 public constant NULL_COLLATERAL_INFO_HASH = bytes16(0);
    address public constant NULL_ADDRESS = address(0x0);
    //********************************************************* */

    //****** */
    // EVENTS
    //****** */
    event LogDebtKernelError(uint8 indexed _errorId, bytes32 indexed _orderHash, string desc);

    event LogFeeTransfer(address indexed payer, address token, uint256 amount, address indexed beneficiary);

    event IssuedNewInputLoans(address[] debtor, uint256[] loanTokenIds);

    event LogDebtOrderFilled(bytes32 _agreementId, uint256 _principal, address _principalToken);

    //********************************************************* */

    /*********** */
    // STRUCTURES
    /*********** */

    struct LoanIssuance {
        address version;
        address[] debtors;
        bytes32[] termsContractParameters; // for different loans
        bytes32[] agreementIds;
        uint256[] salts;
    }

    struct LoanOrder {
        LoanIssuance issuance;
        address principalTokenAddress;
        uint256[] principalAmounts;
        uint256 creditorFee;
        uint256[] expirationTimestampInSecs;
        bytes32[] debtOrderHashes;
        uint8[] riskScores;
        uint8 assetPurpose;
    }

    struct FillDebtOrderParam {
        address[] orderAddresses; // 0-pool, 1-principal token address, 2-repayment router,...
        uint256[] orderValues; //  0-creditorFee, 1-asset purpose,..., [x] principalAmounts, [x] expirationTimestampInSecs, [x] - salts, [x] - riskScores
        bytes32[] termsContractParameters; // Term contract parameters from different farmers, encoded as hash strings
        LoanAssetInfo[] latInfo;
    }

    /*********** */
    // VARIABLES
    /*********** */
    mapping(bytes32 => bool) public issuanceCancelled;
    mapping(bytes32 => bool) public debtOrderCancelled;
    mapping(bytes32 => bool) public debtOrderCompleted;

    /// @notice conclude a loan by stopping lending/loan terms or allowing the loan loss. It takes the creditor, agreement ID, and term contract as input
    function concludeLoan(address creditor, bytes32 agreementId) public virtual;
}
