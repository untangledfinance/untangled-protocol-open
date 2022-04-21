// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts-upgradeable/token/ERC721/presets/ERC721PresetMinterPauserAutoIdUpgradeable.sol';
import '../libraries/ConfigHelper.sol';
import '../storage/Registry.sol';

abstract contract IUntangledERC721 is ERC721PresetMinterPauserAutoIdUpgradeable {
    Registry public registry;

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
