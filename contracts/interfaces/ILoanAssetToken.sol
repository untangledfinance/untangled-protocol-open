// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts-upgradeable/token/ERC721/presets/ERC721PresetMinterPauserAutoIdUpgradeable.sol';
import '../storage/Registry.sol';
import '../base/UntangledBase.sol';
import '../libraries/ConfigHelper.sol';

abstract contract ILoanAssetToken is ERC721PresetMinterPauserAutoIdUpgradeable, IUntangledERC721 {
    Registry public registry;

    mapping(bytes32 => LoanTypes) public agreementToLoanType;

    function initialize(
        Registry _registry,
        string memory name,
        string memory symbol,
        string memory baseTokenURI
    ) public virtual;

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
    ) public virtual;

    function remove(address owner, uint256 tokenId) public virtual;

    function getBeneficiary(uint256 _tokenId) public view virtual returns (address beneficiary);

    function getExpectedRepaymentValues(uint256 tokenId, uint256 timestamp)
    public
    view virtual
    returns (uint256 expectedPrincipal, uint256 expectedInterest);
}
