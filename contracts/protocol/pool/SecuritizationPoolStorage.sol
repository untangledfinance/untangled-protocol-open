// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ERC165Upgradeable} from '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol';

import {ContextUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol';
import {ISecuritizationPoolStorage} from './ISecuritizationPoolStorage.sol';
import {RiskScore} from './base/types.sol';
import {RegistryInjection} from './RegistryInjection.sol';

contract SecuritizationPoolStorage is RegistryInjection, ERC165Upgradeable, ISecuritizationPoolStorage {
    // keccak256(abi.encode(uint256(keccak256("untangled.storage.SecuritizationPoolStorage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant StorageLocation = 0x42988f810f621c79bb2e8db2f913a015fc39ef8eac016043863c6a0d12adbf00;

    modifier onlyIssuingTokenStage() {
        CycleState _state = state();
        require(_state != CycleState.OPEN && _state != CycleState.CLOSED, 'Not in issuing token stage');
        _;
    }

    modifier notClosingStage() {
        require(!isClosedState(), 'SecuritizationPool: Pool in closed state');
        _;
    }

    function _getStorage() internal pure returns (Storage storage $) {
        assembly {
            $.slot := StorageLocation
        }
    }

    function tgeAddress() public view virtual override returns (address) {
        Storage storage $ = _getStorage();
        return $.tgeAddress;
    }

    function pot() public view returns (address) {
        return _getStorage().pot;
    }

    // function _setAmountOwedToOriginator(uint256 _amountOwedToOriginator) internal {
    //     Storage storage $ = _getStorage();
    //     $.amountOwedToOriginator = _amountOwedToOriginator;
    // }

    function amountOwedToOriginator() public view returns (uint256) {
        return _getStorage().amountOwedToOriginator;
    }

    function openingBlockTimestamp() public view override returns (uint64) {
        Storage storage $ = _getStorage();
        return $.openingBlockTimestamp;
    }

    function state() public view override returns (CycleState) {
        return _getStorage().state;
    }

    /// @notice checks if the contract is in a closed state
    function isClosedState() public view override returns (bool) {
        return state() == CycleState.CLOSED;
    }

    function secondTGEAddress() public view virtual override returns (address) {
        return _getStorage().secondTGEAddress;
    }

    function validatorRequired() public view virtual override returns (bool) {
        return _getStorage().validatorRequired;
    }

    function supportsInterface(bytes4 _interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(_interfaceId) || type(ISecuritizationPoolStorage).interfaceId == _interfaceId;
    }
}
