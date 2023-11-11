// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import "./auth.sol";
import {Discounting} from "./discounting.sol";
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';

interface IPoolNAV {
    function addLoan(uint256 loan) external;
    function repayLoan(uint256 loan, uint256 amount) external returns(uint256);
    function file(bytes32 name, uint256 value) external;
    function debt(uint256 loan) external view returns (uint256 loanDebt);
}
