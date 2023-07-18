// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./InventoryLoanRegistry.sol";
import "./InventoryInterestTermsContract.sol";
import '@openzeppelin/contracts/interfaces/IERC20.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import "./ConfigHelper.sol";
import "./Registry.sol";


contract InventoryLoanRepaymentRouter is PausableUpgradeable, OwnableUpgradeable {
    using ConfigHelper for Registry;

    Registry public registry;

    enum Errors {
        DEBT_AGREEMENT_NONEXISTENT,
        PAYER_BALANCE_OR_ALLOWANCE_INSUFFICIENT,
        REPAYMENT_REJECTED_BY_TERMS_CONTRACT
    }

    event LogRepayment(
        bytes32 indexed _agreementId,
        address indexed _payer,
        address indexed _beneficiary,
        uint _amount,
        address _token
    );

    event LogError(uint8 indexed _errorId, bytes32 indexed _agreementId);

    function initialize(Registry _registry) public initializer {
        __Pausable_init_unchained();
        __Ownable_init_unchained();
        registry = _registry;
    }

    // Validate repayment request parametters
    function _assertRepaymentRequest(bytes32 _agreementId, address _payer, uint256 _amount, address _tokenAddress)
    internal
    {
        require(_tokenAddress != address(0), "Token address must different with NULL.");
        require(_amount > 0, "Amount must greater than 0.");

        // Ensure agreement exists.
        require(
            registry.getInventoryLoanRegistry().doesEntryExist(_agreementId),
            "Inventory Debt Registry: Agreement Id does not exists."
        );
    }


    function _doRepay(bytes32 _agreementId, address _payer, uint256 _amount, address _tokenAddress)
    public
    {
        // Notify terms contract
        InventoryLoanRegistry debtRegistry = registry.getInventoryLoanRegistry();

        address termsContract = debtRegistry.getTermsContract(_agreementId);
        address beneficiary = debtRegistry.getBeneficiary(_agreementId);
        address debtor = debtRegistry.getDebtor(_agreementId);

        uint remains = InventoryInterestTermsContract(termsContract).registerRepayment(
            _agreementId,
            _amount,
            _tokenAddress
        );

        // Transfer amount to creditor
        require(
            IERC20(_tokenAddress).transferFrom(_payer, beneficiary, _amount - remains),
            "Unsuccessfully transferred repayment amount to Creditor."
        );

        // Transfer remain amount to debtor
        if (debtor != _payer && remains > 0) {
            require(
                IERC20(_tokenAddress).transferFrom(_payer, debtor, remains),
                "Unsuccessfully transferred repayment amount to Creditor."
            );
        }

        // Log event for repayment
        emit LogRepayment(_agreementId, _payer, beneficiary, _amount - remains, _tokenAddress);
    }

    // Mannual repay by using Fiat tokens
    function repay(bytes32 agreementId, address payer, uint256 amount, address tokenAddress)
    public
    whenNotPaused
    returns (uint)
    {
        _assertRepaymentRequest(agreementId, payer, amount, tokenAddress);
        _doRepay(agreementId, payer, amount, tokenAddress);
        return amount;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
}
