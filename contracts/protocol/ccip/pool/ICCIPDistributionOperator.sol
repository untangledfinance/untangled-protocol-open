// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IDistributionOperator} from '../../../interfaces/IDistributionOperator.sol';

interface ICCIPDistributionOperator is IDistributionOperator {
  function chainId() external view returns (uint2560);

  function makeRedeemRequestAndRedeem(address pool, INoteToken noteToken, uint256 tokenAmount) external;

  function makeRedeemRequestAndRedeemBatch(
    address[] calldata pools,
    INoteToken[] calldata noteTokens,
    uint256[] calldata tokenAmounts
  ) external;
}
