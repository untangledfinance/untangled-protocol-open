// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

// import {ISecuritizationPoolStorage} from './ISecuritizationPoolStorage.sol';

interface ISecuritizationPoolLike {
    function original() external view returns (address);
}

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

abstract contract SecuritizationPoolExtension is ISecuritizationPoolExtension {
    modifier onlyCallInTargetPool() {
        ISecuritizationPoolLike current = ISecuritizationPoolLike(address(this));
        // current contract is not poolImpl, => delegate call
        require(current.original() != address(this), 'Only call in target pool');
        _;
    }
}
