// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '../../../base/UntangledBase.sol';
import '../../../interfaces/ISecuritizationPool.sol';
import {ConfigHelper} from '../../../libraries/ConfigHelper.sol';

contract SecuritizationPoolServiceBase is UntangledBase {
    Registry public registry;

    function initialize(Registry _registry) public initializer {
        __UntangledBase__init(_msgSender());

        registry = _registry;
    }

    uint256[49] private __gap;
}
