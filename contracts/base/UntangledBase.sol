// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol';

import '../libraries/Configuration.sol';

/**
 * @title Untangled's SecuritizationPool contract
 * @notice Abstract contract that serves as a base contract for other contracts in the Untangled system.
 *  It provides functionalities for contract initialization, pausing, and access control.
 * @author Untangled Team
 */
abstract contract UntangledBase is
    Initializable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    AccessControlEnumerableUpgradeable
{
    bytes32 public constant OWNER_ROLE = keccak256('OWNER_ROLE');

    function __UntangledBase__init(address owner) internal onlyInitializing {
        __UntangledBase__init_unchained(owner);
    }

    function __UntangledBase__init_unchained(address owner) internal onlyInitializing {
        __Pausable_init_unchained();
        __ReentrancyGuard_init_unchained();
        __AccessControlEnumerable_init_unchained();

        if (owner == address(0)) owner = _msgSender();

        _setupRole(DEFAULT_ADMIN_ROLE, owner);
        _setupRole(OWNER_ROLE, owner);

        _setRoleAdmin(OWNER_ROLE, OWNER_ROLE);
    }

    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
