// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "./auth.sol";
import {Discounting} from "./discounting.sol";
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';

interface IPoolNAV {
    function addLoan(uint256 loan) external;
    function repayLoan(uint256 loan, uint256 amount) external;
}
