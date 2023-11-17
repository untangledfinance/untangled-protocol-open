// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Configuration} from '../../libraries/Configuration.sol';

interface ISecuritizationTGE {
    enum CycleState {
        INITIATED,
        CROWDSALE,
        OPEN,
        CLOSED
    }

    event UpdateTGEAddress(address tge, address token, Configuration.NOTE_TOKEN_TYPE noteType);
    event UpdatePaidPrincipalAmountSOTByInvestor(address indexed user, uint256 currencyAmount);
    event UpdateReserve(uint256 currencyAmount);
    event UpdateInterestRateSOT(uint32 _interestRateSOT);

    function openingBlockTimestamp() external view returns (uint64);

    function termLengthInSeconds() external view returns (uint64);

    function pot() external view returns (address);

    /// @notice sets the pot address for the contract
    function setPot(address _pot) external;

    /// @dev trigger update reserve when buy note token action happens
    function increaseReserve(uint256 currencyAmount) external;

    /// @dev trigger update reserve
    function decreaseReserve(uint256 currencyAmount) external;

    function tgeAddress() external view returns (address);

    function secondTGEAddress() external view returns (address);

    function sotToken() external view returns (address);

    function jotToken() external view returns (address);

    function underlyingCurrency() external view returns (address);

    function state() external view returns (CycleState);

    function paidPrincipalAmountSOT() external view returns (uint256);

    function paidPrincipalAmountSOTByInvestor(address user) external view returns (uint256);

    function reserve() external view returns (uint256);

    function principalAmountSOT() external view returns (uint256);

    function interestRateSOT() external view returns (uint32); // Annually, support 4 decimals num

    function minFirstLossCushion() external view returns (uint32);

    /// @notice checks if the contract is in a closed state
    function isClosedState() external view returns (bool);

    function totalAssetRepaidCurrency() external view returns (uint256); // Total $ (cUSD) paid for Asset repayment - repayInBatch

    /// @notice injects the address of the Token Generation Event (TGE) and the associated token address
    function injectTGEAddress(
        address _tgeAddress,
        address _tokenAddress,
        Configuration.NOTE_TOKEN_TYPE _noteToken
    ) external;

    /// @dev trigger update asset value repaid
    function increaseTotalAssetRepaidCurrency(uint256 amount) external;

    function redeem(address usr, address notesToken, uint256 currencyAmount, uint256 tokenAmount) external;

    /// @notice checks if the redemption process has finished
    function hasFinishedRedemption() external view returns (bool);

    /// @notice sets the interest rate for the senior tranche of tokens
    function setInterestRateForSOT(uint32 _interestRateSOT) external;

    function claimCashRemain(address recipientWallet) external;
}
