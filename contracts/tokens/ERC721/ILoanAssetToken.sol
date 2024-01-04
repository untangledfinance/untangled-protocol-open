// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import '../../interfaces/IUntangledERC721.sol';
import './types.sol';
import '../../libraries/Configuration.sol';

abstract contract ILoanAssetToken is IUntangledERC721 {

    struct LoanEntry {
        address loanTermContract;
        address debtor;
        address principalTokenAddress;
        bytes32 termsParam; // actually inside this param was already included P token address
        uint256 salt;
        uint256 issuanceBlockTimestamp;
        uint256 expirationTimestamp;
        uint8 riskScore;
        Configuration.ASSET_PURPOSE assetPurpose;
    }

    event UpdateLoanEntry(bytes32 indexed tokenId, LoanEntry entry);

    mapping(bytes32 => LoanEntry) public entries;

    function safeMint(address creditor, LoanAssetInfo calldata latInfo) external virtual;

    /**
     * Record new External Loan to blockchain
     */
    function insert(
        bytes32 tokenId,
        address termContract,
        address debtor,
        bytes32 termsContractParameter,
        address pTokenAddress,
        uint256 _salt,
        uint256 expirationTimestampInSecs,
        uint8[] calldata assetPurposeAndRiskScore
    ) external virtual returns (bool);

    /// @notice retrieves loan information
    function getEntry(bytes32 agreementId) public view virtual returns (LoanEntry memory);

    uint256[50] private __gap;
}
