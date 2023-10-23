// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';

abstract contract Factory is Initializable {
    address public factoryAdmin;

    function __Factory__init(address _factoryAdmin) internal onlyInitializing {
        __Factory__init_unchained(_factoryAdmin);
    }

    function __Factory__init_unchained(address _factoryAdmin) internal onlyInitializing {
        factoryAdmin = _factoryAdmin;
    }

    function _setFactoryAdmin(address _factoryAdmin) internal {
        factoryAdmin = _factoryAdmin;
    }

    // function getSelector(string memory _func) internal pure returns (bytes4) {
    //     return bytes4(keccak256(bytes(_func)));
    // }

    function _deployInstance(address _poolImplAddress, bytes memory _data) internal returns (address) {
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(_poolImplAddress, factoryAdmin, _data);

        return address(proxy);
    }

    uint256[50] private __gap;
}
