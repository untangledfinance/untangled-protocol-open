// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts-upgradeable/token/ERC721/presets/ERC721PresetMinterPauserAutoIdUpgradeable.sol';
import '../storage/Registry.sol';

abstract contract IUntangledERC721 is ERC721PresetMinterPauserAutoIdUpgradeable {
    Registry public registry;

    function __UntangledERC721__init(
        string memory name,
        string memory symbol,
        string memory baseTokenURI
    ) internal onlyInitializing {
        __UntangledERC721__init_unchained(name, symbol, baseTokenURI);
    }

    function __UntangledERC721__init_unchained(
        string memory name,
        string memory symbol,
        string memory baseTokenURI
    ) internal onlyInitializing {
        __ERC721PresetMinterPauserAutoId_init_unchained(name, symbol, baseTokenURI);
    }

    function mint(address to, uint256 tokenId) public virtual onlyRole(MINTER_ROLE) {
        _mint(to, tokenId);
    }

    function getTotalExpectedRepaymentValue(uint256 agreementId, uint256 timestamp)
        external
        view
        virtual
        returns (uint256);

    function getExpirationTimestamp(uint256 agreementId) external view virtual returns (uint256);

    function getInterestRate(uint256 agreementId) external view virtual returns (uint256);

    function getRiskScore(uint256 agreementId) external view virtual returns (uint8);

    function getAssetPurpose(uint256 agreementId) public view virtual returns (Configuration.ASSET_PURPOSE);
}
