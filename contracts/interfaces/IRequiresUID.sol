// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

interface IRequiresUID {
  function hasAllowedUID(address sender) external view returns (bool);
}
