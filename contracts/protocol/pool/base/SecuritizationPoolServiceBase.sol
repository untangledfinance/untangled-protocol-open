// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Registry} from '../../../storage/Registry.sol';
import {UntangledBase} from '../../../base/UntangledBase.sol';
import {ISecuritizationPool} from '../../../interfaces/ISecuritizationPool.sol';
import {ConfigHelper} from '../../../libraries/ConfigHelper.sol';

contract SecuritizationPoolServiceBase is UntangledBase {
    Registry public registry;

    function initialize(Registry _registry) public initializer {
        __UntangledBase__init(_msgSender());

        registry = _registry;
    }

    uint256[49] private __gap;
}
