// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ICCIPSecuritizationManager {
  
  /// @dev Returns the chain ID as a uint256 value.
  /// @return The chain ID as a uint256 value.
  function chainId() view returns (uint256);

  /// @dev Function to buy tokens from the Token Generation Event (TGE) contract.
  /// @param tge The address of the TGE contract.
  /// @param currencyAmount The amount of currency to be used for buying tokens.
  ///
  /// Example Usage:
  /// ```
  /// ISecuritizationManager securitizationManager = ISecuritizationManager(address);
  /// securitizationManager.buyTokens(tgeAddress, amount);
  /// ```
  /// In this example, we create an instance of the `ISecuritizationManager` interface and call the `buyTokens` function, passing the `tgeAddress` and `amount` as arguments.
  ///
  /// Code Analysis:
  /// The `buyTokens` function is called with the `tge` and `currencyAmount` parameters.
  /// The function performs the necessary logic to buy tokens from the TGE contract using the specified currency amount.
  ///
  /// Outputs:
  /// The `buyTokens` function does not have a return value. It performs some internal operations to buy tokens from the TGE contract.
  ///
  function buyTokens(address tge, uint256 currencyAmount) external;
}
