// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import {IUniqueIdentity} from "./IUniqueIdentity.sol";

abstract contract IGo {
  uint256 public constant ID_TYPE_0 = 0; // non-US individual
  uint256 public constant ID_TYPE_1 = 1; // US accredited individual
  uint256 public constant ID_TYPE_2 = 2; // US non accredited individual
  uint256 public constant ID_TYPE_3 = 3; // US entity
  uint256 public constant ID_TYPE_4 = 4; // non-US entity
  uint256 public constant ID_TYPE_5 = 5;
  uint256 public constant ID_TYPE_6 = 6;
  uint256 public constant ID_TYPE_7 = 7;
  uint256 public constant ID_TYPE_8 = 8;
  uint256 public constant ID_TYPE_9 = 9;
  uint256 public constant ID_TYPE_10 = 10;

  /// @notice Returns the address of the UniqueIdentity contract.
  function uniqueIdentity() external virtual returns (IUniqueIdentity);

  function go(address account) public view virtual returns (bool);

  function goOnlyIdTypes(
    address account,
    uint256[] memory onlyIdTypes
  ) public view virtual returns (bool);
}
