// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;

import {Registry} from '../../storage/Registry.sol';

contract RegistryInjection {
    // keccak256(abi.encode(uint256(keccak256("untangled.storage.RegistryInjection")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant RegistryInjectionStorageLocation =
        0x5f6bd0daaaf246715f06ec0ea7e99af4468b70381a38e1f10cb19776ed17ce00;

    event UpdateRegistry(address registry);

    /// @custom:storage-location erc7201:untangled.storage.RegistryInjection
    struct RegistryInjectionStorage {
        Registry registry;
    }

    function _getRegistryInjection() private pure returns (RegistryInjectionStorage storage $) {
        assembly {
            $.slot := RegistryInjectionStorageLocation
        }
    }

    function _setRegistry(Registry _registry) internal {
        RegistryInjectionStorage storage $ = _getRegistryInjection();
        $.registry = _registry;
        emit UpdateRegistry(address(_registry));
    }

    function registry() public view returns (Registry) {
        return _getRegistryInjection().registry;
    }
}
