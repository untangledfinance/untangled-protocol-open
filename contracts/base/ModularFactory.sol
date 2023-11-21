// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import '@openzeppelin/contracts/utils/Create2.sol';
import {AddressUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol';
import {ERC165CheckerUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165CheckerUpgradeable.sol';

import {StorageSlot} from '@openzeppelin/contracts/utils/StorageSlot.sol';

interface IModularProxy {
    event CommitMessage(string message);
    event FunctionUpdate(bytes4 indexed functionId, address indexed oldDelegate, address indexed newDelegate);

    function updateContract(address _delegate, bytes memory data, string calldata commitMessage) external;

    function delegates(bytes4 functionId) external view returns (address);
}

interface IModularImpl {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
    // function initialize(bytes memory data) external returns (bytes4[] memory);
}

contract ModularProxy is IModularProxy {
    using ERC165CheckerUpgradeable for address;
    using AddressUpgradeable for address;

    /**
     * @dev Emitted when the admin account has changed.
     */
    event AdminChanged(address previousAdmin, address newAdmin);

    // funcSig => impl
    mapping(bytes4 => address) internal _delegates;

    modifier ifAdmin() {
        require(msg.sender == _getAdmin(), 'Ownable: caller is not the owner');
        _;
    }

    // keccak256(abi.encode(uint256(keccak256("untangled.storage.ModularFactory")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ModularFactoryStorageLocation =
        0x9aa74cbf2d9c11188ce95836d253f2de04aa615fe1ef8a4e5a1baf80987ca300;

    /// @custom:storage-location erc7201:untangled.storage.ModularFactory
    struct ModularFactoryStorage {
        address admin;
    }

    function _getModularFactoryStorage() private pure returns (ModularFactoryStorage storage $) {
        assembly {
            $.slot := ModularFactoryStorageLocation
        }
    }

    function _getAdmin() internal view returns (address) {
        ModularFactoryStorage storage $ = _getModularFactoryStorage();
        return $.admin;
    }

    function _setAdmin(address newAdmin) private {
        require(newAdmin != address(0), 'Ownable: new admin is the zero address');
        ModularFactoryStorage storage $ = _getModularFactoryStorage();
        $.admin = newAdmin;
    }

    constructor(address _factory) {
        _changeAdmin(_factory);
    }

    function _changeAdmin(address newOwner) internal {
        address oldOwner = _getAdmin();
        _setAdmin(newOwner);
        emit AdminChanged(oldOwner, newOwner);
    }

    function delegates(bytes4 functionId) external view returns (address) {
        return _delegates[functionId];
    }

    function updateContract(address _delegate, bytes memory data, string calldata commitMessage) external ifAdmin {
        require(_delegate != address(0), 'Function does not exist.');

        // delegate must be support ModularImpl
        require(_delegate.supportsInterface(type(IModularImpl).interfaceId), 'Contract is not modular supported');

        bytes memory result = _delegate.functionDelegateCall(data);
        bytes4[] memory _functionSignatures = abi.decode(result, (bytes4[]));

        for (uint i = 0; i < _functionSignatures.length; i++) {
            address oldDelegate = _delegates[_functionSignatures[i]];
            _delegates[_functionSignatures[i]] = _delegate;
            emit FunctionUpdate(_functionSignatures[i], oldDelegate, _delegate);
        }

        emit CommitMessage(commitMessage);
    }

    fallback() external payable {
        address delegate = _delegates[msg.sig];
        require(delegate != address(0), 'Function does not exist.');
        assembly {
            let ptr := mload(0x40)
            calldatacopy(ptr, 0, calldatasize())
            let result := delegatecall(gas(), delegate, ptr, calldatasize(), 0, 0)
            let size := returndatasize()
            returndatacopy(ptr, 0, size)
            switch result
            case 0 {
                revert(ptr, size)
            }
            default {
                return(ptr, size)
            }
        }
    }

    receive() external payable {}
}

abstract contract ModularFactory is Initializable {
    using AddressUpgradeable for address;

    address public factoryAdmin;

    function __Factory__init(address _factoryAdmin) internal onlyInitializing {
        __Factory__init_unchained(_factoryAdmin);
    }

    function __Factory__init_unchained(address _factoryAdmin) internal onlyInitializing {
        factoryAdmin = _factoryAdmin;
    }

    function _setFactoryAdmin(address _factoryAdmin) internal {
        factoryAdmin = _factoryAdmin;
    }

    function _deployInstance(address _poolImplAddress, bytes memory _data, bytes32 salt) internal returns (address) {
        ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(
            Create2.deploy(
                0,
                salt,
                abi.encodePacked(
                    type(TransparentUpgradeableProxy).creationCode,
                    abi.encode(_poolImplAddress, address(this), '')
                )
            )
        );

        proxy.changeAdmin(factoryAdmin);
        address(proxy).functionCall(_data);

        return address(proxy);
    }

    uint256[50] private __gap;
}
