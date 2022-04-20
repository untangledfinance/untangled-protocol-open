// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/interfaces/IERC721.sol';

abstract contract IUntangledERC721 is IERC721 {
    function exists(uint256 tokenId) public view virtual returns (bool);

    function approve(address _to, uint256 _tokenId) public virtual;

    function getTotalExpectedRepaymentValue(uint256 agreementId, uint256 timestamp)
        external
        view
        virtual
        returns (uint256);

    function getExpirationTimestamp(uint256 agreementId) external view virtual returns (uint256);

    function getInterestRate(uint256 agreementId) external view virtual returns (uint256);

    function getRiskScore(uint256 agreementId) external view virtual returns (uint8);

    function getAssetPurpose(uint256 agreementId) external view virtual returns (uint8);

    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) public virtual;

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata tokenIds
    ) external virtual;

    function safeBatchTransferFrom(
        address[] calldata senders,
        address[] calldata recipients,
        uint256[] calldata tokenIds
    ) external virtual;
}
