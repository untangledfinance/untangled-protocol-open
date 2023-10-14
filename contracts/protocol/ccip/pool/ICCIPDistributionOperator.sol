// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IDistributionOperator} from '../../../interfaces/IDistributionOperator.sol';

interface ICCIPDistributionOperator is IDistributionOperator {
  
  /// @dev destinationChainSelector in CCIP
  // @return uint256 The chain selector
  function chainSelector() external view returns (uint256);

  function makeRedeemRequestAndRedeem(address pool, INoteToken noteToken, uint256 tokenAmount) external;

  function makeRedeemRequestAndRedeemBatch(
    address[] calldata pools,
    INoteToken[] calldata noteTokens,
    uint256[] calldata tokenAmounts
  ) external;
}
