// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/presets/ERC1155PresetMinterPauserUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";

contract CollateralManagementToken is ERC1155PresetMinterPauserUpgradeable, ERC1155SupplyUpgradeable {
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
        __ERC1155Supply_init();

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

    /**
     * @dev See {ERC1155-_beforeTokenTransfer}.
     */
    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override(ERC1155SupplyUpgradeable, ERC1155PresetMinterPauserUpgradeable){
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
    public
    view
    override(ERC1155Upgradeable, ERC1155PresetMinterPauserUpgradeable)
    returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
    /**
     * @notice Get total supply of liquidity tokens
     * @param _ids ID of the Tokens
     * @return The total supply of each liquidity token id provided in _ids
   */
    function totalSupplyOfBatch(uint256[] calldata _ids)
    external view returns (uint256[] memory)
    {
        uint256[] memory batchTotalSupplies = new uint256[](_ids.length);
        for (uint256 i = 0; i < _ids.length; i++) {
            batchTotalSupplies[i] = totalSupply(_ids[i]);
        }
        return batchTotalSupplies;
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

