pragma solidity ^0.8.0;

import './ExternalLoanDebtRegistry.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol';
import './ExternalLoanInterestTermsContract.sol';
import '../../storage/ERC20TokenRegistry.sol';
import '../../interfaces/ISecuritizationPool.sol';
import '../../interfaces/ITokenTransferProxy.sol';

/**
 * Repayment Router smart contract for External Loan
 */
contract ExternalLoanRepaymentRouter is IExternalLoanRepaymentRouter {
    using ConfigHelper for Registry;

    Registry public registry;
    enum Errors {
        DEBT_AGREEMENT_NONEXISTENT,
        PAYER_BALANCE_OR_ALLOWANCE_INSUFFICIENT,
        REPAYMENT_REJECTED_BY_TERMS_CONTRACT
    }

    event LogOutputSubmit(bytes32 indexed _agreementId, uint256 indexed _tokenIndex, uint256 _totalAmount);

    function initialize(Registry _registry) public initializer {
        __UntangledBase__init(address(this));
        registry = _registry;
    }

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
    ) internal returns (bool) {
        require(_tokenAddress != address(0), 'Token address must different with NULL.');
        require(_amount > 0, 'Amount must greater than 0.');

        // Ensure agreement exists.
        if (
            !registry.getExternalLoanDebtRegistry().doesEntryExist(_agreementId)
        ) {
            emit LogError(uint8(Errors.DEBT_AGREEMENT_NONEXISTENT), _agreementId);
            return false;
        }

        // Check payer has sufficient balance and has granted router sufficient allowance.
        if (
            ERC20(_tokenAddress).balanceOf(_payer) < _amount ||
            ERC20(_tokenAddress).allowance(_payer, address(registry.getERC20TokenTransferProxy())) < _amount
        ) {
            emit LogError(uint8(Errors.PAYER_BALANCE_OR_ALLOWANCE_INSUFFICIENT), _agreementId);
            return false;
        }
        return true;
    }

    function _doRepay(
        bytes32 _agreementId,
        address _payer,
        uint256 _amount,
        address _tokenAddress
    ) internal returns (bool) {
        // Notify terms contract

        ExternalLoanDebtRegistry externalDebtRegistry = registry.getExternalLoanDebtRegistry();
        address termsContract = externalDebtRegistry.getTermContract(_agreementId);
        address beneficiary = externalDebtRegistry.getBeneficiary(_agreementId);

        uint256 remains = ExternalLoanInterestTermsContract(termsContract).registerRepayment(
            _agreementId,
            _payer,
            beneficiary,
            _amount,
            _tokenAddress
        );

        // Transfer amount to creditor
        if (_payer != address(0x0)) {
            if (
                registry.getPoolManagementLike().isExistingPools(
                    beneficiary
                )
            ) beneficiary = ISecuritizationPool(beneficiary).pot();
            require(
                registry.getERC20TokenTransferProxy().transferFrom(
                    _tokenAddress,
                    _payer,
                    beneficiary,
                    _amount - remains
                ),
                'Unsuccessfully transferred repayment amount to Creditor.'
            );
        }

        // Log event for repayment
        emit LogRepayment(_agreementId, _payer, beneficiary, _amount, _tokenAddress);
        return true;
    }

    // Manual repay by using Fiat tokens
    function repay(
        bytes32 agreementId,
        uint256 amount,
        address tokenAddress
    ) public whenNotPaused returns (uint256) {
        require(
            _assertRepaymentRequest(agreementId, msg.sender, amount, tokenAddress),
            'ExternalLoanRepaymentRouter: Invalid repayment request'
        );
        require(
            _doRepay(agreementId, msg.sender, amount, tokenAddress),
            'ExternalLoanRepaymentRouter: Repayment has failed'
        );
        return amount;
    }

    // Manual repay by using Fiat tokens
    function updateRepaymentByLender(bytes32[] calldata _agreementIds, uint256[] calldata amounts)
        external
        whenNotPaused
        returns (bool)
    {
        uint256 tokenIndex;
        uint256 pAmount;
        address lender;

        ExternalLoanDebtRegistry externalDebtRegistry = registry.getExternalLoanDebtRegistry();

        for (uint256 i = 0; i < _agreementIds.length; i++) {
            (tokenIndex, pAmount, lender) = externalDebtRegistry.principalPaymentInfo(_agreementIds[i]);

            //TODO: Add validation
            // require(lender == msg.sender, "ExternalLoanRepaymentRouter: Invalid caller");

            address tokenAddress = registry.getERC20TokenRegistry()
                .getTokenAddressByIndex(tokenIndex);

            require(
                _doRepay(_agreementIds[i], address(0x0), amounts[i], tokenAddress),
                'ExternalLoanRepaymentRouter: Repayment has failed'
            );

            ERC20PresetMinterPauser(tokenAddress).mint(lender, amounts[i]);

            // (bool success, ) = tokenAddress.call(
            //     abi.encodePacked(
            //         UntangledERC20Token(tokenAddress).mint.selector,
            //         abi.encode(lender, amounts[i])
            //     )
            // );
        }

        emit LogRepayments(_agreementIds, address(this), amounts);

        return true;
    }

    // Manual repay by using Fiat tokens
    function repayInBatch(
        bytes32[] calldata agreementIds,
        uint256[] calldata amounts,
        address tokenAddress
    ) external whenNotPaused returns (bool) {
        for (uint256 i = 0; i < agreementIds.length; i++) {
            require(
                _assertRepaymentRequest(agreementIds[i], msg.sender, amounts[i], tokenAddress),
                'ExternalLoanRepaymentRouter: Invalid repayment request'
            );
            require(
                _doRepay(agreementIds[i], msg.sender, amounts[i], tokenAddress),
                'ExternalLoanRepaymentRouter: Repayment has failed'
            );
        }
        emit LogRepayments(agreementIds, msg.sender, amounts);
        return true;
    }
}
