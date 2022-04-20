// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../storage/Registry.sol';
import '../base/UntangledBase.sol';

abstract contract IMintedIncreasingInterestTGE is UntangledBase {
    function initialize(
        Registry _registry,
        address _pool,
        address _token,
        address _currency,
        bool _isLongSale
    ) public virtual;
}
