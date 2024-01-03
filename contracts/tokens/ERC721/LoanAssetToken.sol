// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {ILoanInterestTermsContract} from '../../interfaces/ILoanInterestTermsContract.sol';
import {ILoanAssetToken} from './ILoanAssetToken.sol';
import {ConfigHelper} from '../../libraries/ConfigHelper.sol';
import {LATValidator} from './LATValidator.sol';
import {Registry} from '../../storage/Registry.sol';
import {LoanAssetInfo, VALIDATOR_ROLE, VALIDATOR_ADMIN_ROLE} from '../ERC721/types.sol';
import {Configuration} from '../../libraries/Configuration.sol';
import {UntangledMath} from '../../libraries/UntangledMath.sol';

/**
 * LoanAssetToken: The representative for ownership of a Loan
 */
contract LoanAssetToken is ILoanAssetToken, LATValidator {
    using ConfigHelper for Registry;

    modifier onlyLoanKernel() {
        require(_msgSender() == address(registry.getLoanKernel()), 'LoanRegistry: Only LoanKernel');
        _;
    }

    /** CONSTRUCTOR */
    function initialize(
        Registry _registry,
        string memory name,
        string memory symbol,
        string memory baseTokenURI
    ) public initializer {
        __UntangledERC721__init(name, symbol, baseTokenURI);
        __LATValidator_init();

        registry = _registry;

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        require(
            address(registry.getSecuritizationManager()) != address(0x0),
            'SECURITIZATION_MANAGER is zero address.'
        );

        _setupRole(VALIDATOR_ADMIN_ROLE, address(registry.getSecuritizationManager()));
        _setRoleAdmin(VALIDATOR_ROLE, VALIDATOR_ADMIN_ROLE);

        require(address(registry.getLoanKernel()) != address(0x0), 'LOAN_KERNEL is zero address.');

        _setupRole(MINTER_ROLE, address(registry.getLoanKernel()));
        _revokeRole(MINTER_ROLE, _msgSender());
    }

    function getExpirationTimestamp(uint256 _tokenId) public view override returns (uint256) {
        return entries[bytes32(_tokenId)].expirationTimestamp;
    }

    function getRiskScore(uint256 _tokenId) public view override returns (uint8) {
        return entries[bytes32(_tokenId)].riskScore;
    }

    function getAssetPurpose(uint256 _tokenId) public view override returns (Configuration.ASSET_PURPOSE) {
        return entries[bytes32(_tokenId)].assetPurpose;
    }

    function getInterestRate(uint256 _tokenId) public view override returns (uint256 beneficiary) {
        return registry.getLoanInterestTermsContract().getInterestRate(bytes32(_tokenId));
    }

    /**
     * Record new Loan to blockchain
     */
    /// @dev Records a new loan entry by inserting loan details into the entries mapping
    function insert(
        bytes32 tokenId,
        address termContract,
        address debtor,
        bytes32 termsContractParameter,
        address pTokenAddress,
        uint256 _salt,
        uint256 expirationTimestampInSecs,
        uint8[] calldata assetPurposeAndRiskScore
    ) external override whenNotPaused onlyLoanKernel returns (bool) {
        require(termContract != address(0x0), 'LoanRegistry: Invalid term contract');
        LoanEntry memory newEntry = LoanEntry({
            loanTermContract: termContract,
            debtor: debtor,
            principalTokenAddress: pTokenAddress,
            termsParam: termsContractParameter,
            salt: _salt, //solium-disable-next-line security
            issuanceBlockTimestamp: block.timestamp,
            lastRepayTimestamp: 0,
            expirationTimestamp: expirationTimestampInSecs,
            assetPurpose: Configuration.ASSET_PURPOSE(assetPurposeAndRiskScore[0]),
            riskScore: assetPurposeAndRiskScore[1]
        });
        entries[tokenId] = newEntry;

        emit UpdateLoanEntry(tokenId, newEntry);
        return true;
    }

    /// @inheritdoc ILoanAssetToken
    function getEntry(bytes32 agreementId) public view override returns (LoanEntry memory) {
        return entries[agreementId];
    }

    function safeMint(
        address creditor,
        LoanAssetInfo calldata latInfo
    ) public virtual override onlyRole(MINTER_ROLE) validateCreditor(creditor, latInfo) {
        for (uint i = 0; i < latInfo.tokenIds.length; i = UntangledMath.uncheckedInc(i)) {
            _safeMint(creditor, latInfo.tokenIds[i]);
        }
    }

    function isValidator(address sender) public view virtual override returns (bool) {
        return hasRole(VALIDATOR_ROLE, sender);
    }

    uint256[50] private __gap;
}
