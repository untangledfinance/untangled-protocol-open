// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IPauseable} from '../../base/IPauseable.sol';
import '../../base/UntangledBase.sol';
import '../../base/Factory.sol';
import '../../libraries/ConfigHelper.sol';
import '../../libraries/UntangledMath.sol';
import './IPoolNAVFactory.sol';

contract PoolNAVFactory is UntangledBase, Factory, IPoolNAVFactory {
    using ConfigHelper for Registry;

    bytes4 constant POOL_NAV_INIT_FUNC_SELECTOR = bytes4(keccak256('initialize(address,address)'));

    Registry public registry;

    address public override poolNAVImplementation;

    function initialize(Registry _registry, address _factoryAdmin) public initializer {
        __UntangledBase__init(_msgSender());
        __Factory__init(_factoryAdmin);

        registry = _registry;
    }

    function setFactoryAdmin(address _factoryAdmin) public onlyAdmin {
        _setFactoryAdmin(_factoryAdmin);
    }

    function setPoolNAVImplementation(address newAddress) external onlyAdmin {
        require(newAddress != address(0), 'PoolNAVFactory: new address cannot be zero');
        poolNAVImplementation = newAddress;
        emit UpdatePoolNAVImplementation(newAddress);
    }

    function createPoolNAV() external override whenNotPaused returns (address) {
        address pool = _msgSender();
        bytes memory _initialData = abi.encodeWithSelector(POOL_NAV_INIT_FUNC_SELECTOR, registry, pool);
        address poolNAV = _deployInstance(poolNAVImplementation, _initialData);
        return poolNAV;
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IPoolNAVFactory).interfaceId || super.supportsInterface(interfaceId);
    }
}
