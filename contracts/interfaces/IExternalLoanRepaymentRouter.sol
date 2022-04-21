pragma solidity ^0.8.0;

import '../storage/ERC20TokenRegistry.sol';
import '../interfaces/ISecuritizationPool.sol';
import "../base/UntangledBase.sol";
import "../storage/Registry.sol";

/**
 * Repayment Router smart contract for External Loan
 */
abstract contract IExternalLoanRepaymentRouter is UntangledBase {
    enum Errors {
        DEBT_AGREEMENT_NONEXISTENT,
        PAYER_BALANCE_OR_ALLOWANCE_INSUFFICIENT,
        REPAYMENT_REJECTED_BY_TERMS_CONTRACT
    }

    event LogOutputSubmit(bytes32 indexed _agreementId, uint256 indexed _tokenIndex, uint256 _totalAmount);

    function initialize(
        Registry _registry
    ) public virtual;

    event LogRepayment(
        bytes32 indexed _agreementId,
        address indexed _payer,
        address indexed _beneficiary,
        uint256 _amount,
        address _token
    );

    event LogRepayments(bytes32[] _agreementIds, address _payer, uint256[] _amounts);

    event LogError(uint8 indexed _errorId, bytes32 indexed _agreementId);

    function _assertRepaymentRequest(
        bytes32 _agreementId,
        address _payer,
        uint256 _amount,
        address _tokenAddress
    ) internal virtual returns (bool);

    function _doRepay(
        bytes32 _agreementId,
        address _payer,
        uint256 _amount,
        address _tokenAddress
    ) internal virtual returns (bool);

    // Manual repay by using Fiat tokens
    function repay(
        bytes32 agreementId,
        uint256 amount,
        address tokenAddress
    ) public virtual returns (uint256);

    // Manual repay by using Fiat tokens
    function updateRepaymentByLender(bytes32[] calldata _agreementIds, uint256[] calldata amounts)
        external
        virtual
        returns (bool);

    // Manual repay by using Fiat tokens
    function repayInBatch(
        bytes32[] calldata agreementIds,
        uint256[] calldata amounts,
        address tokenAddress
    ) external virtual returns (bool);
}
