// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import './InvoiceFinanceInterestTermsContract.sol';
import './InvoiceFinanceInterestTermsContract.sol';
import './InvoiceDebtRegistry.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol';
import '@openzeppelin/contracts/interfaces/IERC721.sol';

/**
*  Escrow account that hold all callaterals for Loans
*/
contract InvoiceCollateralizer is Initializable, PausableUpgradeable, AccessControlEnumerableUpgradeable, IERC721ReceiverUpgradeable {
    using SafeMath for uint256;
    using ConfigHelper for Registry;
    using Unpack for bytes32;

    Registry public registry;

    bytes32 public constant COLLATERALIZER = keccak256('COLLATERALIZER');

    // Collateralizer here refers to the owner of the asset that is being collateralized.
    mapping(bytes32 => address) public agreementToCollateralizer;

    ///////////////////////////////
    // CONSTANTS               ///
    /////////////////////////////
    uint256 public constant SECONDS_IN_DAY = 24 * 60 * 60;
    string public constant CONTEXT = 'InvoiceCollateralizer';
    string public constant CONTEXT_COLLATERAL_SALE = 'collateral_sale';

    ///////////////////////////////
    // EVENTS                  ///
    /////////////////////////////
    event InvoiceCollateralLocked(
        bytes32 indexed agreementID,
        address indexed token,
        uint256 tokenId
    );

    event CollateralReturned(
        bytes32 indexed agreementID,
        address indexed collateralizer,
        address token,
        uint256 amount
    );

    function initialize(Registry _registry) public initializer {
        __Pausable_init_unchained();
        __AccessControlEnumerable_init_unchained();
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        registry = _registry;
    }

    ///////////////////////////////
    // MODIFIERS               ///
    /////////////////////////////

    modifier onlyPermissionedInvoiceTermContract(bytes32 agreementId) {
        require(
            msg.sender ==
            registry.getInvoiceDebtRegistry()
            .getTermsContract(agreementId),
            'Collateralizer: Sender must be Term Contract of current Debt.'
        );
        _;
    }

    ///////////////////////////////
    // INTERNAL FUNCTIONS     ////
    /////////////////////////////
    // Paramerters from Loan which have collateral is Invoice
    function retrieveInvoiceCollateralParameters(bytes32 agreementId)
    internal
    view
    returns (
        address collateralToken,
        uint256[] memory invoiceTokenIds,
        uint256 gracePeriodInDays,
        InvoiceFinanceInterestTermsContract termsContract
    )
    {
        address termsContractAddress;
        bytes32 termsContractParameters;

        // Pull the terms contract and associated parameters for the agreement
        InvoiceDebtRegistry invoiceDebtRegistry = registry.getInvoiceDebtRegistry();
        (termsContractAddress, termsContractParameters) = invoiceDebtRegistry
        .getTerms(agreementId);

        invoiceTokenIds = invoiceDebtRegistry.getInvoiceTokenIds(agreementId);

        gracePeriodInDays = termsContractParameters.unpackGracePeriodInDays();

        // Resolve address of token associated with this agreement in token registry
        collateralToken = address(registry.getAcceptedInvoiceToken());
        termsContract = InvoiceFinanceInterestTermsContract(
            termsContractAddress
        );
    }

    ///////////////////////////////
    // EXTERNAL FUNCTIONS     ///
    /////////////////////////////
    function collateralizeERC721(bytes32 agreementId, address collateralizer)
    public
    onlyRole(COLLATERALIZER)
    whenNotPaused
    returns (bool)
    {
        uint256[] memory invoiceTokenIds;
        address collateralToken;
        InvoiceFinanceInterestTermsContract termsContract;

        // Fetch all relevant collateralization parameters
        (
        collateralToken,
        invoiceTokenIds,
        ,
        termsContract
        ) = retrieveInvoiceCollateralParameters(agreementId);

        require(
            address(termsContract) == msg.sender,
            'Collateralizer: Sender must be Term Contract smart contract.'
        );

        require(
            agreementToCollateralizer[agreementId] == address(0),
            'Collateralizer: This Debt must be not collateralized.'
        );

        AcceptedInvoiceToken invoiceToken = AcceptedInvoiceToken(
            collateralToken
        );
        address custodian = address(this);
        // store collaterallizer in mapping, effectively demarcating that the
        // agreement is now collateralized.
        agreementToCollateralizer[agreementId] = collateralizer;
        uint256 invoiceTokenIdsLength = invoiceTokenIds.length;
        for (uint256 i = 0; i < invoiceTokenIdsLength; i++) {
            /*
            The collateralizer must have sufficient balance equal to or greater
            than the amount being put up for collateral.
            */
            require(
                invoiceToken.ownerOf(invoiceTokenIds[i]) == collateralizer,
                'Invoice Collateralizer: Collateralizer must owner of invoice.'
            );

            // the collateral must be successfully transferred to this contract, via a proxy.
            invoiceToken.safeTransferFrom(
                collateralizer,
                custodian,
                invoiceTokenIds[i]
            );

            // emit event that collateral has been secured.
            emit InvoiceCollateralLocked(
                agreementId,
                address(registry.getAcceptedInvoiceToken()),
                invoiceTokenIds[i]
            );
        }

        return true;
    }

    /**
    * Add more collateral to increase CR
    */
    function additionERC721Collateralize(
        bytes32 agreementId,
        address collateralizer,
        bytes32 invoiceTokenId,
        address token
    )
    public
    onlyRole(COLLATERALIZER)
    whenNotPaused
    returns (bool _success)
    {
        address collateralToken;
        InvoiceFinanceInterestTermsContract termsContract;

        (
        collateralToken,
        ,
        ,
        termsContract
        ) = retrieveInvoiceCollateralParameters(agreementId);

        require(
            address(termsContract) == msg.sender,
            'Collateralizer: Sender must be Term Contract smart contract.'
        );

        require(
            collateralToken == token,
            'InvoiceCollateralizer: Invalid collateral token.'
        );

        AcceptedInvoiceToken invoiceToken = AcceptedInvoiceToken(
            collateralToken
        );
        address custodian = address(this);

        require(
            invoiceToken.ownerOf(uint256(invoiceTokenId)) == collateralizer,
            'Invoice Collateralizer: Collateralizer must owner of invoice.'
        );

        // the collateral must be successfully transferred to this contract, via a proxy.
        invoiceToken.safeTransferFrom(collateralizer, custodian, uint256(invoiceTokenId));

        return true;
    }

    function withdrawERC721Collateralize(
        bytes32 agreementId,
        address collateralizer,
        bytes32 invoiceTokenId,
        address token
    )
    public
    onlyRole(COLLATERALIZER)
    whenNotPaused
    returns (bool _success)
    {
        if (agreementToCollateralizer[agreementId] != address(0)) {
            // The token in which collateral is denominated
            address collateralToken;
            // The terms contract according to which this asset is being collateralized.
            InvoiceFinanceInterestTermsContract termsContract;

            (
            collateralToken,
            ,
            ,
            termsContract
            ) = retrieveInvoiceCollateralParameters(agreementId);

            require(
                address(termsContract) == msg.sender,
                'Collateralizer: Sender must be Term Contract smart contract.'
            );

            require(
                collateralToken == token,
                'InvoiceCollateralizer: Invalid collateral token.'
            );
            require(
                collateralizer == agreementToCollateralizer[agreementId],
                'InvoiceCollateralizer: Invalid debtor of agreement'
            );

            // transfer the collateral this contract was holding in escrow back to collateralizer.
            AcceptedInvoiceToken invoiceToken = AcceptedInvoiceToken(
                collateralToken
            );

            require(
                invoiceToken.ownerOf(uint256(invoiceTokenId)) == address(this),
                'Invoice Collateralizer: Collateralizer must owner of invoice.'
            );

            invoiceToken.safeTransferFrom(address(this), collateralizer, uint256(invoiceTokenId));

            // stop financing
//            invoiceToken.stopFinancing(invoiceTokenId);
        }

        return true;
    }

    /**
     * Returns collateral to the debt agreement's original collateralizer
     * if and only if the debt agreement's term has lapsed and
     * the total expected repayment value has been repaid.
     *
     * @param agreementId bytes32 The debt agreement's ID
     */
    function returnInvoiceCollateral(bytes32 agreementId)
    public
    whenNotPaused
    onlyPermissionedInvoiceTermContract(agreementId)
    returns (bool)
    {
        if (agreementToCollateralizer[agreementId] != address(0)) {
            // The token in which collateral is denominated
            address collateralToken;

            // Fetch all relevant collateralization parameters.
            (collateralToken,,,) = retrieveInvoiceCollateralParameters(
                agreementId
            );

            InvoiceDebtRegistry invoiceDebtRegistry = registry.getInvoiceDebtRegistry();

            // Ensure a valid form of collateral is tied to this agreement id
            require(
                collateralToken != address(0),
                'Collateral token must different with NULL.'
            );
            // Ensure that the debt is not in a state of default
            // Ensure Value Repaid to date is greater or equal expected value until this Debt expired
            require(
                invoiceDebtRegistry.isCompletedRepayment(agreementId),
                'Debtor have not completed repayment.'
            );
            // determine collateralizer of the collateral.
            address collateralizer = agreementToCollateralizer[agreementId];

            // Mark agreement's collateral as withdrawn by setting the agreement's
            // collateralizer to 0x0.
            delete agreementToCollateralizer[agreementId];

            // transfer the collateral this contract was holding in escrow back to collateralizer.
            uint256[] memory invoiceTokenIds = invoiceDebtRegistry
            .getInvoiceTokenIds(agreementId);
            if (invoiceTokenIds.length > 0) {
                AcceptedInvoiceToken invoiceToken = registry.getAcceptedInvoiceToken();

                for (uint256 i = 0; i < invoiceTokenIds.length; ++i) {
                    if (invoiceToken.ownerOf(uint256(invoiceTokenIds[i])) != address(0)) {
                        IERC721(collateralToken).safeTransferFrom(address(this), collateralizer, invoiceTokenIds[i]);
                        // stop financing
                        // invoiceToken.stopFinancing(bytes32(invoiceTokenIds[i]));

                        // log the return event.
                        emit CollateralReturned(
                            agreementId,
                            collateralizer,
                            collateralToken,
                            uint256(invoiceTokenIds[i])
                        );
                    }
                }
            }

        }

        return true;
    }

    // For receiving AIT token
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /**
    *
    */
    function timestampAdjustedForGracePeriod(uint256 gracePeriodInDays)
    public
    view
    returns (uint256)
    {
        return block.timestamp.sub(SECONDS_IN_DAY.mul(gracePeriodInDays));
    }

    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
