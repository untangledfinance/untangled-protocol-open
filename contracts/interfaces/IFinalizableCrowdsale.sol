

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


interface IFinalizableCrowdsale {
    event CrowdsaleFinalized();

    function finalized() external view returns (bool);
}
