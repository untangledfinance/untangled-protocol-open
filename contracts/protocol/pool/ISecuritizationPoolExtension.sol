// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

// import {ISecuritizationPoolStorage} from './ISecuritizationPoolStorage.sol';

/**
 * @title Untangled's SecuritizationPool contract
 * @notice Main entry point for senior LPs (a.k.a. capital providers)
 *  Automatically invests across borrower pools using an adjustable strategy.
 * @author Untangled Team
 */
interface ISecuritizationPoolExtension {
    function installExtension(bytes memory params) external;

    function getFunctionSignatures() external view returns (bytes4[] memory);
}
