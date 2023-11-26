// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {ERC165Upgradeable} from '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol';

import {ContextUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol';
import {ISecuritizationPoolStorage} from './ISecuritizationPoolStorage.sol';
import {RiskScore} from './base/types.sol';
import {RegistryInjection} from './RegistryInjection.sol';
import {ISecuritizationPoolExtension, SecuritizationPoolExtension} from './SecuritizationPoolExtension.sol';

import 'hardhat/console.sol';

contract SecuritizationPoolStorage is
    RegistryInjection,
    ERC165Upgradeable,
    ISecuritizationPoolStorage,
    SecuritizationPoolExtension
{
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

    function installExtension(bytes memory params) public virtual override onlyCallInTargetPool {
        __SecuritizationPoolStorage_init_unchained(abi.decode(params, (NewPoolParams)));
    }

    function __SecuritizationPoolStorage_init_unchained(NewPoolParams memory _newPoolParams) internal {}

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
        return
            super.supportsInterface(_interfaceId) ||
            type(ISecuritizationPoolStorage).interfaceId == _interfaceId ||
            type(ISecuritizationPoolExtension).interfaceId == _interfaceId;
    }

    function getFunctionSignatures() public view virtual override returns (bytes4[] memory) {
        bytes4[] memory _functionSignatures = new bytes4[](9);

        _functionSignatures[0] = this.amountOwedToOriginator.selector;
        _functionSignatures[1] = this.tgeAddress.selector;
        _functionSignatures[2] = this.secondTGEAddress.selector;
        _functionSignatures[3] = this.state.selector;
        _functionSignatures[4] = this.isClosedState.selector;
        _functionSignatures[5] = this.pot.selector;
        _functionSignatures[6] = this.validatorRequired.selector;
        _functionSignatures[7] = this.openingBlockTimestamp.selector;
        _functionSignatures[8] = this.supportsInterface.selector;

        return _functionSignatures;
    }
}
