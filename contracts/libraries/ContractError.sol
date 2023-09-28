// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

library ContractError {
    error SecuritizationPoolInvalidCurrency();
    error SecuritizationPoolAssetNotExisted();
    error SecuritizationPoolMinFirstLostGreaterThan100();
    error SecuritizationPoolCurrencyApprovalFailed();
}
