// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '../../interfaces/IUntangledERC721.sol';

abstract contract ILoanAssetToken is IUntangledERC721 {
    function safeMint(address to, uint256 tokenId, uint256 nonce, address validators, bytes memory signatures) public virtual;
}
