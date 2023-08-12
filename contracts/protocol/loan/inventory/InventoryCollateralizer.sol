// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../../loan/inventory/InventoryInterestTermsContract.sol";
import '@openzeppelin/contracts-upgradeable/interfaces/IERC721ReceiverUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/interfaces/IERC1155ReceiverUpgradeable.sol';
import '@openzeppelin/contracts/interfaces/IERC1155.sol';
import '@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol';
import "../../../base/UntangledBase.sol";
import "../../../libraries/ConfigHelper.sol";
import "../../../storage/Registry.sol";
import "./InventoryLoanRegistry.sol";
import "../../../tokens/ERC721/invoice/AcceptedInvoiceToken.sol";


/**
*  Escrow account that hold all callaterals for Loans
*/
contract InventoryCollateralizer is IERC721ReceiverUpgradeable, IERC1155ReceiverUpgradeable, UntangledBase {
    using SafeMath for uint;
    using ConfigHelper for Registry;

    Registry public registry;

    bytes32 public constant COLLATERALIZER = keccak256('COLLATERALIZER');

    // Collateralizer here refers to the owner of the asset that is being collateralized.
    mapping(bytes32 => address) public agreementToCollateralizer;

    ///////////////////////////////
    // CONSTANTS               ///
    /////////////////////////////
    uint public constant SECONDS_IN_DAY = 24 * 60 * 60;
    string public constant CONTEXT = "InventoryCollateralizer";
    string public constant CONTEXT_COLLATERAL_SALE = "collateral_sale";

    ///////////////////////////////
    // EVENTS                  ///
    /////////////////////////////
    event CollateralReturned(
        bytes32 indexed agreementID,
        address indexed collateralizer,
        address token,
        uint amount
    );

    function initialize(Registry _registry) public initializer {
        __UntangledBase__init_unchained(_msgSender());
        registry = _registry;
    }

    ///////////////////////////////
    // MODIFIERS               ///
    /////////////////////////////

    modifier onlyPermissionedInventoryTermContract(bytes32 agreementId) {
        require(
            msg.sender == registry.getInventoryLoanRegistry().getTermsContract(agreementId),
            "InventoryCollateralizer: Sender must be Term Contract of current Debt."
        );
        _;
    }

    ///////////////////////////////
    // INTERNAL FUNCTIONS     ////
    /////////////////////////////
    function _unpackLoanTermsParametersFromBytes(bytes32 parameters)
    internal
    pure
    returns (
        uint _principalTokenIndex,
        uint _principalAmount,
        uint _interestRate,
        uint _amortizationUnitType,
        uint _termLengthInAmortizationUnits,
        uint _gracePeriodInDays
    )
    {
        // The first byte of the parameters encodes the principal token's index in the
        // token registry.
        bytes32 principalTokenIndexShifted = parameters & 0xff00000000000000000000000000000000000000000000000000000000000000;
        // The subsequent 12 bytes of the parameters encode the PRINCIPAL AMOUNT.
        bytes32 principalAmountShifted = parameters & 0x00ffffffffffffffffffffffff00000000000000000000000000000000000000;
        // The subsequent 3 bytes of the parameters encode the INTEREST RATE.
        bytes32 interestRateShifted = parameters & 0x00000000000000000000000000ffffff00000000000000000000000000000000;
        // The subsequent 4 bits (half byte) encode the AMORTIZATION UNIT TYPE code.
        bytes32 amortizationUnitTypeShifted = parameters & 0x00000000000000000000000000000000f0000000000000000000000000000000;
        // The subsequent 12 bytes encode the term length, as denominated in
        // the encoded amortization unit.
        bytes32 termLengthInAmortizationUnitsShifted = parameters & 0x000000000000000000000000000000000ffffffffffffffffffffffff0000000;

        bytes32 gracePeriodInDaysShifted = parameters & 0x000000000000000000000000000000000000000000000000000000000ff00000;

        return (
        uint(principalTokenIndexShifted >> 248),
        uint(principalAmountShifted >> 152),
        uint(interestRateShifted >> 128),
        uint(amortizationUnitTypeShifted >> 124),
        uint(termLengthInAmortizationUnitsShifted >> 28),
        uint(gracePeriodInDaysShifted >> 20)
        );
    }

    function _unpackInventoryCollateralParametersFromBytes(bytes16 collateralParams)
    internal
    pure
    returns (uint, uint)
    {
        bytes16 collateralTokenIdShifted = collateralParams & 0xffffffff000000000000000000000000;
        bytes16 collateralAmountShifted = collateralParams & 0x00000000ffffffffffffffffffffffff;

        return (
        uint256(uint128(collateralTokenIdShifted) >> 96),
        uint256(uint128(collateralAmountShifted))
        );
    }

    // Parameters from Loan which have collateral is Inventory
    function retrieveInventoryCollateralParameters(bytes32 agreementId)
    internal
    view
    returns (
        address collateralToken,
        uint _collateralAmount,
        uint256 _collateralTokenId,
        uint gracePeriodInDays,
        InventoryInterestTermsContract termsContract
    )
    {
        address termsContractAddress;
        bytes32 termsContractParameters;
        bytes16 collateralInfoParameters;

        // Pull the terms contract and associated parameters for the agreement
        (
        termsContractAddress,
        termsContractParameters,
        collateralInfoParameters
        ) = registry.getInventoryLoanRegistry().getTerms(agreementId);

        // Unpack terms contract parameters in order to get inventory collateralization-specific params
        (_collateralTokenId, _collateralAmount) = _unpackInventoryCollateralParametersFromBytes(collateralInfoParameters);
        (,,,,, gracePeriodInDays) = _unpackLoanTermsParametersFromBytes(termsContractParameters);

        // Resolve address of token associated with this agreement in token registry
        collateralToken = address(registry.getCollateralManagementToken());
        termsContract = InventoryInterestTermsContract(termsContractAddress);
    }

    ///////////////////////////////
    // EXTERNAL FUNCTIONS     ///
    /////////////////////////////

    /**
     * Transfers collateral from the debtor to the current contract, as custodian.
     *
     * @param agreementId bytes32 The debt agreement's ID
     * @param collateralizer address The owner of the asset being collateralized
     */
    function collateralizeERC1155(
        bytes32 agreementId,
        address debtor,
        address collateralizer
    )
    public
    onlyRole(COLLATERALIZER)
    whenNotPaused
    {
        // The token in which collateral is denominated
        address collateralToken;
        // The amount being put up for collateral
        uint collateralAmount;
        // erc1155 token id
        uint256 collateralTokenId;
        // The number of days a debtor has after a debt enters default
        // before their collateral is eligible for seizure.
        uint gracePeriodInDays;
        // The terms contract according to which this asset is being collateralized.
        InventoryInterestTermsContract termsContract;

        // Fetch all relevant collateralization parameters
        (
        collateralToken,
        collateralAmount,
        collateralTokenId,
        gracePeriodInDays,
        termsContract
        ) = retrieveInventoryCollateralParameters(agreementId);

        require(
            address(termsContract) == msg.sender,
            "InventoryCollateralizer: Sender must be Term Contract smart contract."
        );
        require(
            collateralAmount > 0,
            "InventoryCollateralizer: Collateral amount must greater than 0."
        );
        require(
            collateralToken != address(0),
            "InventoryCollateralizer: Token address must differ with address null."
        );

        require(
            agreementToCollateralizer[agreementId] == address(0),
            "InventoryCollateralizer: This Debt must be not collateralized."
        );

        IERC1155 erc1155token = IERC1155(collateralToken);
        address custodian = address(this);

        // agreement is now collateralized.
        agreementToCollateralizer[agreementId] = debtor;

        IERC1155(erc1155token).safeTransferFrom(
            collateralizer,
            custodian,
            collateralTokenId,
            collateralAmount, "");
    }

    /**
    * Add more collateral to increase CR
    */
    function additionInventoryCollateralize(
        bytes32 agreementId,
        address collateralizer,
        uint amount,
        address token
    )
    public
    onlyRole(COLLATERALIZER)
    whenNotPaused
    {

        // The token in which collateral is denominated
        address collateralToken;
        uint256 collateralTokenId;
        // The terms contract according to which this asset is being collateralized.
        InventoryInterestTermsContract termsContract;

        (collateralToken,,collateralTokenId,,termsContract) = retrieveInventoryCollateralParameters(agreementId);

        require(
            address(termsContract) == msg.sender,
            "InventoryCollateralizer: Sender must be Term Contract smart contract."
        );

        require(
            amount > 0,
            "InventoryCollateralizer: Collateral amount must greater than 0."
        );
        require(
            collateralToken == token,
            "InventoryCollateralizer: Invalid collateral token."
        );

        IERC1155 erc1155token = IERC1155(collateralToken);
        address custodian = address(this);

        require(
            erc1155token.balanceOf(collateralizer, collateralTokenId) >= amount,
            "InventoryCollateralizer: Balance of collateralizer must sufficient with required amount."
        );

        erc1155token.safeTransferFrom(
            collateralizer,
            custodian,
            collateralTokenId,
            amount, "");
    }

    /**
    * withdraw more collateral to decrease CR
    */
    function withdrawInventoryCollateralize(
        bytes32 agreementId,
        address collateralizer,
        uint amount,
        address token
    )
    public
    onlyRole(COLLATERALIZER)
    whenNotPaused
    {
        require(agreementToCollateralizer[agreementId] != address(0), "Invalid agreedmentId");

        // The token in which collateral is denominated
        address collateralToken;
        uint collateralAmount;
        uint256 collateralTokenId;
        // The terms contract according to which this asset is being collateralized.
        InventoryInterestTermsContract termsContract;

        (collateralToken,collateralAmount,collateralTokenId,,termsContract) = retrieveInventoryCollateralParameters(agreementId);

        require(
            address(termsContract) == msg.sender,
            "InventoryCollateralizer: Sender must be Term Contract smart contract."
        );
        require(
            amount > 0,
            "InventoryCollateralizer: Withdraw amount must greater than 0."
        );
        require(
            collateralAmount >= amount,
            "InventoryCollateralizer: Withdraw amount must less or equal collateral amount."
        );
        require(
            collateralToken == token,
            "InventoryCollateralizer: Invalid collateral token."
        );
        require(collateralizer == agreementToCollateralizer[agreementId], "InventoryCollateralizer: Invalid debtor of agreement");

        IERC1155(collateralToken).safeTransferFrom(
            address(this),
            collateralizer,
            collateralTokenId,
            amount,
            ""
        );

        // log the return event.
        emit CollateralReturned(
            agreementId,
            collateralizer,
            collateralToken,
            collateralAmount
        );
    }

    function burnInventoryCollateralize(
        bytes32 agreementId,
        uint amount,
        address token
    )
    public
    onlyRole(COLLATERALIZER)
    whenNotPaused
    {

        // The token in which collateral is denominated
        address collateralToken;
        uint256 collateralTokenId;
        // The terms contract according to which this asset is being collateralized.
        InventoryInterestTermsContract termsContract;

        (collateralToken,,collateralTokenId,,termsContract) = retrieveInventoryCollateralParameters(agreementId);

        require(
            address(termsContract) == msg.sender,
            "InventoryCollateralizer: Sender must be Term Contract smart contract."
        );

        require(
            amount > 0,
            "InventoryCollateralizer: Collateral amount must greater than 0."
        );
        require(
            collateralToken == token,
            "InventoryCollateralizer: Invalid collateral token."
        );

        ERC1155Burnable erc1155token = ERC1155Burnable(collateralToken);

        erc1155token.burn(address(this), collateralTokenId, amount);
    }

    /**
     * Returns collateral to the debt agreement's original collateralizer
     * if and only if the debt agreement's term has lapsed and
     * the total expected repayment value has been repaid.
     *
     * @param agreementId bytes32 The debt agreement's ID
     */
    function returnInventoryCollateral(
        bytes32 agreementId
    )
    public
    whenNotPaused
    onlyPermissionedInventoryTermContract(agreementId)
    {
        require(agreementToCollateralizer[agreementId] != address(0), "Invalid agreementId");
        // The token in which collateral is denominated
        address collateralToken;
        // The amount being put up for collateral
        uint collateralAmount;
        uint256 collateralTokenId;

        // The number of days a debtor has after a debt enters default
        // before their collateral is eligible for seizure.
        uint gracePeriodInDays;
        // The terms contract according to which this asset is being collateralized.
        InventoryInterestTermsContract termsContract;

        // Fetch all relevant collateralization parameters.
        (
        collateralToken,
        collateralAmount,
        collateralTokenId,
        gracePeriodInDays,
        termsContract
        ) = retrieveInventoryCollateralParameters(agreementId);

        // Ensure a valid form of collateral is tied to this agreement id
        require(collateralToken != address(0), "Collateral token must different with NULL.");

        InventoryLoanRegistry inventoryLoanDebtRegistry = registry.getInventoryLoanRegistry();
        // Ensure that the debt is not in a state of default
        // Ensure Value Repaid to date is greater or equal expected value until this Debt expired
        require(
            inventoryLoanDebtRegistry.completedRepayment(agreementId),
            "Debtor have not completed repayment."
        );

        // determine collateralizer of the collateral.
        address collateralizer = agreementToCollateralizer[agreementId];

        // Mark agreement's collateral as withdrawn by setting the agreement's
        // collateralizer to 0x0.
        delete agreementToCollateralizer[agreementId];

        if (collateralAmount > 0) {
            ERC1155(collateralToken).safeTransferFrom(
                address(this),
                collateralizer,
                collateralTokenId,
                collateralAmount,
                ""
            );
        }

        // stop financing invoices
        uint256[] memory invoiceTokenIds = inventoryLoanDebtRegistry.getInvoiceIds(agreementId);
        if (invoiceTokenIds.length > 0) {
            AcceptedInvoiceToken invoiceToken = registry.getAcceptedInvoiceToken();

            for (uint i = 0; i < invoiceTokenIds.length; ++i) {
                registry.getAcceptedInvoiceToken().transferFrom(
                    address(this),
                    collateralizer,
                    invoiceTokenIds[i]
                );
                // stop financing
                // TODO tanlm temporary disable
                //                    invoiceToken.stopInventoryFinancing(bytes32(invoiceTokenIds[i]));
            }
        }

        // log the return event.
        emit CollateralReturned(
            agreementId,
            collateralizer,
            collateralToken,
            collateralAmount
        );
    }

    // For receiving AIT token
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes memory data) public returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
    external returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
    external returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    /**
    *
    */
    function timestampAdjustedForGracePeriod(uint gracePeriodInDays)
    public
    view
    returns (uint)
    {
        return block.timestamp.sub(
            SECONDS_IN_DAY.mul(gracePeriodInDays)
        );
    }

}
