// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import '../base/UntangledBase.sol';
import '../storage/Registry.sol';

abstract contract ILoanRepaymentRouter is UntangledBase {
    Registry public registry;

    enum Errors {
        DEBT_AGREEMENT_NONEXISTENT,
        PAYER_BALANCE_OR_ALLOWANCE_INSUFFICIENT,
        REPAYMENT_REJECTED_BY_TERMS_CONTRACT
    }

    event LogOutputSubmit(bytes32 indexed _agreementId, uint256 indexed _tokenIndex, uint256 _totalAmount);

    function initialize(Registry _registry) public virtual;

    event LogRepayment(
        bytes32 indexed _agreementId,
        address indexed _payer,
        address indexed _beneficiary,
        uint256 _amount,
        address _token
    );

    event LogRepayments(bytes32[] _agreementIds, address _payer, uint256[] _amounts);

    event LogError(uint8 indexed _errorId, bytes32 indexed _agreementId);

    /// @notice allows batch repayment of multiple loans by iterating over the given agreement IDs and amounts
    /// @dev calls _assertRepaymentRequest and _doRepay for each repayment, and emits the LogRepayments event to indicate the successful batch repayment
    function repayInBatch(
        bytes32[] calldata agreementIds,
        uint256[] calldata amounts,
        address tokenAddress
    ) external virtual returns (bool);

    uint256[49] private __gap;
}
