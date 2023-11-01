// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '../../../storage/Registry.sol';
import '../../../interfaces/INoteToken.sol';

interface IPoolNAVFactory {
    event UpdatePoolNAVImplementation(address indexed newAddress);

    function setPoolNAVImplementation(address newAddress) external;

    function poolNAVImplementation() external view returns (address);

    function createPoolNAV() external returns (address);
}
