// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IPauseable} from '../../../base/IPauseable.sol';
import '../../../base/UntangledBase.sol';
import '../../../base/Factory.sol';
import '../../../libraries/ConfigHelper.sol';
import '../../../libraries/UntangledMath.sol';
import {MINTER_ROLE} from '../../../tokens/ERC20/types.sol';
import "./IPoolNAVFactory.sol";

contract PoolNAVFactory is UntangledBase, Factory, IPoolNAVFactory {
    using ConfigHelper for Registry;

    bytes4 constant POOL_NAV_INIT_FUNC_SELECTOR = bytes4(keccak256('initialize(address)'));

    Registry public registry;

    address public override poolNAVImplementation;

    function initialize(Registry _registry, address _factoryAdmin) public reinitializer(3) {
        __UntangledBase__init(_msgSender());
        __Factory__init(_factoryAdmin);

        registry = _registry;
    }

    function setFactoryAdmin(address _factoryAdmin) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setFactoryAdmin(_factoryAdmin);
    }

    function setPoolNAVImplementation(address newAddress) external onlyAdmin {
        require(newAddress != address(0), 'PoolNAVFactory: new address cannot be zero');
        poolNAVImplementation = newAddress;
        emit UpdatePoolNAVImplementation(newAddress);
    }

    function createPoolNAV() external override whenNotPaused nonReentrant returns (address) {
        bytes memory _initialData = abi.encodeWithSelector(
            POOL_NAV_INIT_FUNC_SELECTOR,
            _msgSender()
        );

        address poolNAV = _deployInstance(poolNAVImplementation, _initialData);

        return poolNAV;
    }

    uint256[46] private __gap0;
    uint256[50] private __gap;
}
