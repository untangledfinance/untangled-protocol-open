// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {Configuration} from '../../libraries/Configuration.sol';

interface ISecuritizationPoolNAV {
    /// Events
    event IncreaseDebt(uint256 indexed loan, uint256 currencyAmount);
    event DecreaseDebt(uint256 indexed loan, uint256 currencyAmount);
    event SetRate(uint256 indexed loan, uint256 rate);
    event ChangeRate(uint256 indexed loan, uint256 newRate);
    event File(bytes32 indexed what, uint256 rate, uint256 value);

    // events
    event SetLoanMaturity(uint256 indexed loan, uint256 maturityDate_);
    event WriteOff(uint256 indexed loan, uint256 indexed writeOffGroupsIndex, bool override_);
    event AddLoan(uint256 indexed loan, uint256 principalAmount, uint256 maturityDate);
    event Repay(uint256 indexed loan, uint256 currencyAmount);
    event UpdateAssetRiskScore(uint256 loan, uint256 risk);

    function addLoan(uint256 loan) external returns (uint256);

    function repayLoan(uint256 loan, uint256 amount) external returns (uint256);

    function file(bytes32 name, uint256 value) external;

    function file(
        bytes32 name,
        uint256 rate_,
        uint256 writeOffPercentage_,
        uint256 overdueDays_,
        uint256 penaltyRate_,
        uint256 riskIndex
    ) external;

    function debt(uint256 loan) external view returns (uint256 loanDebt);

    function risk(bytes32 nft_) external view returns (uint256 risk_);

    /// @notice calculates and returns the current NAV
    /// @return nav_ current NAV
    function currentNAV() external view returns (uint256 nav_);

    function currentNAVAsset(bytes32 tokenId) external view returns (uint256);

    function futureValue(bytes32 nft_) external view returns (uint256);

    function maturityDate(bytes32 nft_) external view returns (uint256);

    function discountRate() external view returns (uint256);

    function updateAssetRiskScore(bytes32 nftID_, uint256 risk_) external;
}
