// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '../../interfaces/IUntangledERC721.sol';
import './types.sol';

abstract contract ILoanAssetToken is IUntangledERC721 {
  
  function safeMint(address creditor, LoanAssetInfo calldata latInfo) external virtual;

  uint256[50] private __gap;
}
