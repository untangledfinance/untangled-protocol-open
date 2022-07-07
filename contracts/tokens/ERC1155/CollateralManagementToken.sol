// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/presets/ERC1155PresetMinterPauserUpgradeable.sol";

contract CollateralManagementToken is ERC1155PresetMinterPauserUpgradeable {
    string private _name;
    string private _symbol;

    function initialize(
        address minter,
        string memory name,
        string memory symbol,
        string memory uri
    ) public initializer {
        _name = name;
        _symbol = symbol;
        __ERC1155PresetMinterPauser_init(uri);

        _setupRole(MINTER_ROLE, minter);
        renounceRole(MINTER_ROLE, _msgSender());
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the name.
     */
    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function balanceOfProjects(address _owner, uint256[] calldata _projectIds) external view returns (uint256[] memory) {
        // The balance of any account can be calculated from the Transfer events history.
        // However, since we need to keep the balances to validate transfer request,
        // there is no extra cost to also privide a querry function.

        uint256[] memory balanceOfWallets = new uint256[](_projectIds.length);

        for (uint i = 0; i < _projectIds.length; i++) {
            balanceOfWallets[i] = balanceOf(_owner, _projectIds[i]);
        }

        return balanceOfWallets;
    }
}

