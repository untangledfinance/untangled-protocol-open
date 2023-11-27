// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ContextUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol';
import {RegistryInjection} from './RegistryInjection.sol';

import {OWNER_ROLE, ORIGINATOR_ROLE} from './types.sol';

import {ISecuritizationAccessControl} from './ISecuritizationAccessControl.sol';

contract SecuritizationAccessControl is ContextUpgradeable, RegistryInjection, ISecuritizationAccessControl {
    // // keccak256(abi.encode(uint256(keccak256("untangled.storage.SecuritizationAccessControl")) - 1)) & ~bytes32(uint256(0xff))
    // bytes32 private constant SecuritizationAccessControlStorageLocation =
    //     0xb38e00afe21f8bf8961a30ad85d453b5f474f19414b8973dee80c89fb0d97b00;
    // /// @custom:storage-location erc7201:untangled.storage.SecuritizationAccessControl
    // struct SecuritizationAccessControlStorage {
    //     mapping(address => mapping(bytes32 => bool)) roles;
    // }
    // function _getSecuritizationAccessControl() private pure returns (SecuritizationAccessControlStorage storage $) {
    //     assembly {
    //         $.slot := SecuritizationAccessControlStorageLocation
    //     }
    // }
    // modifier onlyOwner() {
    //     address account = _msgSender();
    //     require(isOwner(account), 'AccessControl: caller is not an owner');
    //     _;
    // }
    // modifier onlyRole(bytes32 role) {
    //     require(hasRole(role, _msgSender()), 'AccessControl: caller is not an originator');
    //     _;
    // }
    // function __SecuritizationAccessControl_init_unchained(address _owner) internal onlyInitializing {
    //     _setRole(OWNER_ROLE, _owner);
    // }
    // function hasRole(bytes32 role, address account) public view override returns (bool) {
    //     SecuritizationAccessControlStorage storage $ = _getSecuritizationAccessControl();
    //     return $.roles[account][role];
    // }
    // function isOwner(address account) public view override returns (bool) {
    //     return hasRole(OWNER_ROLE, account);
    // }
    // function grantRole(bytes32 role, address account) public virtual override onlyOwner {
    //     SecuritizationAccessControlStorage storage $ = _getSecuritizationAccessControl();
    //     $.roles[account][role] = true;
    //     emit RoleGranted(role, account, _msgSender());
    // }
    // function revokeRole(bytes32 role, address account) public virtual override onlyOwner {
    //     SecuritizationAccessControlStorage storage $ = _getSecuritizationAccessControl();
    //     $.roles[account][role] = false;
    //     emit RoleRevoked(role, account, _msgSender());
    // }
    // function _setRole(bytes32 role, address account) internal virtual {
    //     SecuritizationAccessControlStorage storage $ = _getSecuritizationAccessControl();
    //     $.roles[account][role] = true;
    //     emit RoleRevoked(role, account, _msgSender());
    // }
    // function _revokeRole(bytes32 role, address account) internal virtual {
    //     SecuritizationAccessControlStorage storage $ = _getSecuritizationAccessControl();
    //     $.roles[account][role] = false;
    //     emit RoleRevoked(role, account, _msgSender());
    // }
    // function renounceRole(bytes32 role, address account) public virtual override {
    //     require(account == _msgSender(), 'AccessControl: can only renounce roles for self');
    //     _revokeRole(role, account);
    // }
}
