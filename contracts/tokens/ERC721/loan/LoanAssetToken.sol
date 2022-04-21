pragma solidity ^0.8.0;

import '../../../protocol/loan/ExternalLoanDebtRegistry.sol';
import '../../../protocol/loan/ExternalLoanInterestTermsContract.sol';
import '../../../storage/Registry.sol';
import '../../../constants/LoanTyping.sol';
import "../../../interfaces/ILoanAssetToken.sol";
import '../../../libraries/Configuration.sol';

/**
 * LoanAssetToken: The representative for ownership of a Loan
 */
contract LoanAssetTokenImplementation is ILoanAssetToken {
    using ConfigHelper for Registry;
    // old
    bytes32 public constant BURN_ROLE = keccak256("BURN_ROLE");

    /** CONSTRUCTOR */
    function initialize(
        Registry _registry,
        string memory name,
        string memory symbol,
        string memory baseTokenURI
    ) public override initializer {
        __ERC721PresetMinterPauserAutoId_init(name, symbol, baseTokenURI);
        _setupRole(BURN_ROLE, _msgSender());
        registry = _registry;
    }

    //************* *IERC20TokenRegistry/
    // INTERNAL
    //************* */
    /**
     * _modifyBeneficiary mutates the debt registry. This function should be
     * called every time a token is transferred or minted
     */
    function _modifyBeneficiary(uint256 _tokenId, address _to) internal {
        ExternalLoanDebtRegistry externalLoanDebtRegistry = registry.getExternalLoanDebtRegistry();
        if (externalLoanDebtRegistry.getBeneficiary(bytes32(_tokenId)) != _to) {
            externalLoanDebtRegistry.modifyBeneficiary(bytes32(_tokenId), _to);
        }
    }

    //************************** */
    // EXTERNAL
    //************************** */

    //----------------
    // SEND
    //----------------
    /**
     * Mints a unique LAT token and inserts the associated issuance into
     * the loan registry, if the calling address is authorized to do so.
     */
    function externalLoanCreate(
        bytes32 latTokenId,
        address creditor,
        address termContract,
        address debtor,
        bytes32 termsParam,
        uint256 pTokenIndex,
        uint256 salt,
        uint256 expirationTimestampInSecs,
        uint8[] memory assetPurposeAndRiskScore
    ) public {
        ExternalLoanDebtRegistry externalLoanRegistry = registry.getExternalLoanDebtRegistry();
        externalLoanRegistry.insert(
            latTokenId,
            creditor,
            termContract,
            debtor,
            termsParam,
            pTokenIndex,
            salt,
            expirationTimestampInSecs,
            assetPurposeAndRiskScore
        );
        super._mint(creditor, uint256(latTokenId));
        agreementToLoanType[latTokenId] = LoanTypes.EXTERNAL;
    }

    /**
     * We override transferFrom methods of the parent ERC721Token
     * contract to allow its functionality to be frozen in the case of an emergency
     */
    function transferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) public whenNotPaused {
        _modifyBeneficiary(_tokenId, _to);
        super.transferFrom(_from, _to, _tokenId);
    }

    /**
     * We override safeTransferFrom methods of the parent ERC721Token
     * contract to allow its functionality to be frozen in the case of an emergency
     */
    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) public whenNotPaused {
        _modifyBeneficiary(_tokenId, _to);
        super.safeTransferFrom(_from, _to, _tokenId);
    }

    /**
     * We override safeTransferFrom methods of the parent ERC721Token
     * contract to allow its functionality to be frozen in the case of an emergency
     */
    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId,
        bytes memory _data
    ) public whenNotPaused {
        _modifyBeneficiary(_tokenId, _to);
        super.safeTransferFrom(_from, _to, _tokenId, _data);
    }

    function safeBatchTransferFrom(
        address[] calldata senders,
        address[] calldata recipients,
        uint256[] calldata tokenIds
    ) external whenNotPaused {
        require(senders.length == tokenIds.length, 'senders and tokens id length mismatch');
        require(recipients.length == tokenIds.length, 'recipients and tokens id length mismatch');

        for (uint256 i = 0; i < tokenIds.length; ++i) {
            super.safeTransferFrom(senders[i], recipients[i], tokenIds[i]);
            _modifyBeneficiary(tokenIds[i], recipients[i]);
        }
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata tokenIds
    ) external {
        for (uint256 i = 0; i < tokenIds.length; ++i) {
            super.safeTransferFrom(from, to, tokenIds[i]);
            _modifyBeneficiary(tokenIds[i], to);
        }
    }

    function remove(address owner, uint256 tokenId) public whenNotPaused {
        require(hasRole(BURN_ROLE, _msgSender()), "ERC721PresetMinterPauserAutoId: must have burner role to burn");
        super._burn(owner, tokenId);
    }

    function getExpectedRepaymentValues(uint256 tokenId, uint256 timestamp)
        public
        view
        returns (uint256 expectedPrincipal, uint256 expectedInterest)
    {
        bytes32 agreementId = bytes32(tokenId);
        (expectedPrincipal, expectedInterest) = registry.getExternalLoanInterestTermsContract()
            .getExpectedRepaymentValues(agreementId, timestamp);
    }

    function getBeneficiary(uint256 _tokenId) public view returns (address beneficiary) {
        return
            registry.getExternalLoanDebtRegistry().getBeneficiary(
                bytes32(_tokenId)
            );
    }

    function getExpirationTimestamp(uint256 _tokenId) public view returns (uint256) {
        return
            registry.getExternalLoanDebtRegistry().getExpirationTimestamp(
                bytes32(_tokenId)
            );
    }

    function getRiskScore(uint256 _tokenId) public view returns (uint8) {
        return
        registry.getExternalLoanDebtRegistry().getRiskScore(
                bytes32(_tokenId)
            );
    }

    function getAssetPurpose(uint256 _tokenId) public view returns (uint8) {
        return
        registry.getExternalLoanDebtRegistry().getAssetPurpose(
                bytes32(_tokenId)
            );
    }

    function getInterestRate(uint256 _tokenId) public view returns (uint256 beneficiary) {
        return
        registry.getExternalLoanInterestTermsContract()
                .getInterestRate(bytes32(_tokenId));
    }

    function getTotalExpectedRepaymentValue(uint256 agreementId, uint256 timestamp)
        public
        view
        returns (uint256 expectedRepaymentValue)
    {
        uint256 principalAmount;
        uint256 interestAmount;
        (principalAmount, interestAmount) = getExpectedRepaymentValues(agreementId, timestamp);
        expectedRepaymentValue = principalAmount.add(interestAmount);
    }

    function exists(uint256 tokenId) public view returns (bool) {
        return super._exists(tokenId);
    }
}
