// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

import {AccessControlUpgradeable} from '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract ExampleResolver is AccessControlUpgradeable {
    bytes32 public constant CCIP_RECEIVER_ROLE = keccak256('CCIP_RECEIVER_ROLE');

    function __ExampleResolver_init_unchained(address owner) internal onlyInitializing {
        _setupRole(CCIP_RECEIVER_ROLE, owner);
    }

    function hello() external onlyRole(CCIP_RECEIVER_ROLE) {
        ///
        // check role
        // msgSender == UntangedReceiver
    }
}
