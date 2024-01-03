// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import '@openzeppelin/contracts-upgradeable/token/ERC721/presets/ERC721PresetMinterPauserAutoIdUpgradeable.sol';
import '@openzeppelin/contracts/utils/Strings.sol';

import '../../storage/Registry.sol';

abstract contract IUntangledERC721 is ERC721PresetMinterPauserAutoIdUpgradeable {
    Registry public registry;

    string private _baseTokenURI;

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
        _baseTokenURI = baseTokenURI;
        __ERC721PresetMinterPauserAutoId_init_unchained(name, symbol, baseTokenURI);
    }

    function mint(address to, uint256 tokenId) public virtual onlyRole(MINTER_ROLE) {
        _mint(to, tokenId);
    }

    function safeMint(address to, uint256 tokenId) public virtual onlyRole(MINTER_ROLE) {
        _safeMint(to, tokenId);
    }

    function setBaseURI(string memory baseTokenURI) public virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        _baseTokenURI = baseTokenURI;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireMinted(tokenId);

        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, Strings.toHexString(tokenId))) : '';
    }

    /// @notice the expiration timestamp of an invoice/loan token
    function getExpirationTimestamp(uint256 agreementId) external view virtual returns (uint256);

    /// @notice  the interest rate associated with an token
    function getInterestRate(uint256 agreementId) external view virtual returns (uint256);

    /// @notice the risk score associated with a token
    function getRiskScore(uint256 agreementId) external view virtual returns (uint8);

    /// @notice retrieves the asset purpose for a given loan agreement ID
    function getAssetPurpose(uint256 agreementId) public view virtual returns (Configuration.ASSET_PURPOSE);

    uint256[48] private __gap;
}
