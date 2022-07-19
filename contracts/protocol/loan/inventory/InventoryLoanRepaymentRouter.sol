pragma solidity ^0.5.10;
import "../../libraries/openzeppelin/Pausable.sol";
import "../../token/TokenTransferProxy.sol";
import "./InventoryLoanDebtRegistry.sol";
import "./InventoryInterestTermsContract.sol";

contract InventoryLoanRepaymentRouter is BinkabiContext, Pausable {

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

    constructor(address contractRegistryAddress) public BinkabiContext(contractRegistryAddress) {
    }

    // Validate repayment request parametters
    function _assertRepaymentRequest(bytes32 _agreementId, address _payer, uint256 _amount, address _tokenAddress)
    internal
    returns (bool)
    {
        require(_tokenAddress != address(0), "Token address must different with NULL.");
        require(_amount > 0, "Amount must greater than 0.");

        // Ensure agreement exists.
        require(
            InventoryLoanDebtRegistry(contractRegistry.get(INVENTORY_LOAN_DEBT_REGISTRY)).doesEntryExist(_agreementId),
            "Inventory Debt Registry: Agreement Id does not exists."
        );

        // Check payer has sufficient balance and has granted router sufficient allowance.
        if (ERC20(_tokenAddress).balanceOf(_payer) < _amount ||
        ERC20(_tokenAddress).allowance(_payer, address(contractRegistry.get(ERC20_TOKEN_TRANSFER_PROXY))) < _amount) {
            emit LogError(uint8(Errors.PAYER_BALANCE_OR_ALLOWANCE_INSUFFICIENT), _agreementId);
            return false;
        }
        return true;
    }


    function _doRepay(bytes32 _agreementId, address _payer, uint256 _amount, address _tokenAddress)
    public
    returns (bool)
    {
        // Notify terms contract
        InventoryLoanDebtRegistry debtRegistry = InventoryLoanDebtRegistry(contractRegistry.get(INVENTORY_LOAN_DEBT_REGISTRY));

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
            TokenTransferProxy(contractRegistry.get(ERC20_TOKEN_TRANSFER_PROXY)).transferFrom(_tokenAddress, _payer, beneficiary, _amount - remains),
            "Unsuccessfully transferred repayment amount to Creditor."
        );

        // Transfer remain amount to debtor
        if (debtor != _payer && remains > 0) {
            require(
                TokenTransferProxy(contractRegistry.get(ERC20_TOKEN_TRANSFER_PROXY)).transferFrom(_tokenAddress, _payer, debtor, remains),
                "Unsuccessfully transferred repayment amount to Creditor."
            );
        }

        // Log event for repayment
        emit LogRepayment(_agreementId, _payer, beneficiary, _amount - remains, _tokenAddress);
        return true;
    }

    // Mannual repay by using Fiat tokens
    function repay(bytes32 agreementId, address payer, uint256 amount, address tokenAddress)
    public
    whenNotPaused
    returns (uint)
    {
        require(
            _assertRepaymentRequest(agreementId, payer, amount, tokenAddress),
            "InventoryLoanRepaymentRouter: Invalid repayment request"
        );
        require(
            _doRepay(agreementId, payer, amount, tokenAddress),
            "InventoryLoanRepaymentRouter: Repayment has failed"
        );
        return amount;
    }
}
