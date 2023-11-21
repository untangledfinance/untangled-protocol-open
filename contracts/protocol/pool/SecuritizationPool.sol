// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.19;

// import {AccessControlEnumerableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol';
// import {ERC165Upgradeable} from '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol';
// import {IERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol';
// import {ERC20BurnableUpgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol';
// import {IERC721ReceiverUpgradeable} from '@openzeppelin/contracts-upgradeable/interfaces/IERC721ReceiverUpgradeable.sol';
// import {IAccessControlUpgradeable} from '@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol';
// import {PausableUpgradeable} from '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
// import {ERC165CheckerUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165CheckerUpgradeable.sol';
// import {StringsUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol';

// import {IUntangledERC721} from '../../interfaces/IUntangledERC721.sol';
// import {INoteToken} from '../../interfaces/INoteToken.sol';
// import {ICrowdSale} from '../note-sale/crowdsale/ICrowdSale.sol';

// import {ISecuritizationPool} from './ISecuritizationPool.sol';
// import {ISecuritizationPoolValueService} from './ISecuritizationPoolValueService.sol';

// import {MintedIncreasingInterestTGE} from '../note-sale/MintedIncreasingInterestTGE.sol';
// import {ConfigHelper} from '../../libraries/ConfigHelper.sol';
// import {Configuration} from '../../libraries/Configuration.sol';
// import {UntangledMath} from '../../libraries/UntangledMath.sol';
// import {Registry} from '../../storage/Registry.sol';
// import {FinalizableCrowdsale} from './../note-sale/crowdsale/FinalizableCrowdsale.sol';
// import {POOL_ADMIN, ORIGINATOR_ROLE, RATE_SCALING_FACTOR} from './types.sol';

// import {ISecuritizationLockDistribution} from './ISecuritizationLockDistribution.sol';
// import {SecuritizationLockDistribution} from './SecuritizationLockDistribution.sol';
// import {SecuritizationTGE} from './SecuritizationTGE.sol';
// import {ISecuritizationTGE} from './ISecuritizationTGE.sol';
// import {RegistryInjection} from './RegistryInjection.sol';

// import {SecuritizationAccessControl} from './SecuritizationAccessControl.sol';
// import {ISecuritizationAccessControl} from './ISecuritizationAccessControl.sol';

// import {RiskScore} from './base/types.sol';

// import {ISecuritizationPoolExtension} from './ISecuritizationPoolExtension.sol';

// /**
//  * @title Untangled's SecuritizationPool contract
//  * @notice Main entry point for senior LPs (a.k.a. capital providers)
//  *  Automatically invests across borrower pools using an adjustable strategy.
//  * @author Untangled Team
//  */
// contract SecuritizationPoolModular {
//     using ConfigHelper for Registry;
//     using ERC165CheckerUpgradeable for address;

//     event CommitMessage(string message);
//     event FunctionUpdate(bytes4 indexed functionId, address indexed oldDelegate, address indexed newDelegate);

//     // keccak256(abi.encode(uint256(keccak256("untangled.storage.SecuritizationPoolModularStorage")) - 1)) & ~bytes32(uint256(0xff))
//     bytes32 private constant SecuritizationPoolModularStorageLocation =
//         0x42a7eee116f254cdf692648cfa55e8537fb7d745a2dfa800395d3834ff1eef00;

//     /// @custom:storage-location erc7201:untangled.storage.SecuritizationPoolModularStorage
//     struct SecuritizationPoolModularStorage {
//         mapping(address => bytes4[]) modulars;
//         mapping(bytes4 => address) delegates;
//     }

//     function _getSecuritizationPoolModularStorage() private pure returns (SecuritizationPoolModularStorage storage $) {
//         assembly {
//             $.slot := SecuritizationPoolModularStorageLocation
//         }
//     }

//     function updateContract(address delegate) public {
//         require(
//             delegate.supportsInterface(type(ISecuritizationPoolExtension).interfaceId),
//             'SecuritizationPool: Invalid delegate'
//         );

//         bytes4[] memory sigs = ISecuritizationPoolExtension(delegate).getFunctionSignatures();
//         SecuritizationPoolModularStorage storage $ = _getSecuritizationPoolModularStorage();

//         $.modulars[delegate] = sigs;
//         for (uint256 i = 0; i < sigs.length; i++) {
//             address oldDelegate = $.delegates[sigs[i]];
//             $.delegates[sigs[i]] = delegate;
//             emit FunctionUpdate(sigs[i], oldDelegate, delegate);
//         }

//         emit CommitMessage(string(abi.encodePacked('Update contract: ', StringsUpgradeable.toHexString(delegate))));
//     }

//     /**
//      * @dev Fallback function that delegates calls to the address returned by `_implementation()`. Will run if call data
//      * is empty.
//      */
//     receive() external payable virtual {
//         _fallback();
//     }

//     /**
//      * @dev Hook that is called before falling back to the implementation. Can happen as part of a manual `_fallback`
//      * call, or as part of the Solidity `fallback` or `receive` functions.
//      *
//      * If overridden should call `super._beforeFallback()`.
//      */
//     function _beforeFallback() internal virtual {}

//     /**
//      * @dev Delegates the current call to the address returned by `_implementation()`.
//      *
//      * This function does not return to its internal call site, it will return directly to the external caller.
//      */
//     function _fallback() internal virtual {
//         _beforeFallback();

//         _delegate(_implementation());
//     }

//     /**
//      * @dev This is a virtual function that should be overridden so it returns the address to which the fallback function
//      * and {_fallback} should delegate.
//      */
//     function _implementation() internal view virtual returns (address) {}

//     /**
//      * @dev Delegates the current call to `implementation`.
//      *
//      * This function does not return to its internal call site, it will return directly to the external caller.
//      */
//     function _delegate(address implementation) internal virtual {
//         assembly {
//             // Copy msg.data. We take full control of memory in this inline assembly
//             // block because it will not return to Solidity code. We overwrite the
//             // Solidity scratch pad at memory position 0.
//             calldatacopy(0, 0, calldatasize())

//             // Call the implementation.
//             // out and outsize are 0 because we don't know the size yet.
//             let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)

//             // Copy the returned data.
//             returndatacopy(0, 0, returndatasize())

//             switch result
//             // delegatecall returns 0 on error.
//             case 0 {
//                 revert(0, returndatasize())
//             }
//             default {
//                 return(0, returndatasize())
//             }
//         }
//     }
// }

import {ERC165Upgradeable} from '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol';
import {AddressUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol';
import {ContextUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';

import {StorageSlot} from '@openzeppelin/contracts/utils/StorageSlot.sol';
import {ERC165CheckerUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165CheckerUpgradeable.sol';
import {RegistryInjection} from './RegistryInjection.sol';
import {ISecuritizationPool} from './ISecuritizationPool.sol';

import {ISecuritizationTGE} from './ISecuritizationTGE.sol';
import {ISecuritizationPoolExtension} from './ISecuritizationPoolExtension.sol';

import {Registry} from '../../storage/Registry.sol';
import {RATE_SCALING_FACTOR} from './types.sol';

contract SecuritizationPool is Initializable, ContextUpgradeable, ERC165Upgradeable, RegistryInjection {
    using AddressUpgradeable for address;
    using ERC165CheckerUpgradeable for address;

    event CommitMessage(string message);
    event FunctionUpdate(bytes4 indexed functionId, address indexed oldDelegate, address indexed newDelegate);

    // keccak256(abi.encode(uint256(keccak256("untangled.storage.ModularFactory")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ModularFactoryStorageLocation =
        0x9aa74cbf2d9c11188ce95836d253f2de04aa615fe1ef8a4e5a1baf80987ca300;

    /// @custom:storage-location erc7201:untangled.storage.ModularFactory
    struct ModularFactoryStorage {
        // funcSig => impl
        mapping(bytes4 => address[]) _delegates;
    }

    function _getModularFactoryStorage() private pure returns (ModularFactoryStorage storage $) {
        assembly {
            $.slot := ModularFactoryStorageLocation
        }
    }

    function getExtension(bytes4 funcId) public view returns (address[] memory) {
        ModularFactoryStorage storage $ = _getModularFactoryStorage();
        return $._delegates[funcId];
    }

    function registerExtension(address _delegate, string calldata commitMessage) external {
        // bytes4[] memory functionIds = ISecuritizationPoolExtension(_delegate);
        require(
            _delegate.supportsInterface(type(ISecuritizationPoolExtension).interfaceId),
            'Not an ISecuritizationPoolExtension'
        );

        bytes4[] memory functionIds = ISecuritizationPoolExtension(_delegate).getFunctionSignatures();
        mapping(bytes4 => address[]) storage delegates = _getModularFactoryStorage()._delegates;
        for (uint i = 0; i < functionIds.length; ++i) {
            address oldDelegate = address(0);
            if (delegates[functionIds[i]].length > 0) {
                oldDelegate = delegates[functionIds[i]][delegates[functionIds[i]].length - 1];
            }
            
            delegates[functionIds[i]].push(_delegate);
            emit FunctionUpdate(functionIds[i], address(0), _delegate);
        }

        emit CommitMessage(commitMessage);
    }

    constructor() {
        _disableInitializers();
    }

    /** CONSTRUCTOR */
    function initialize(
        Registry registry_,
        bytes memory params
    )
        public
        // address _currency,
        // uint32 _minFirstLossCushion
        initializer
    {
        ISecuritizationPool.NewPoolParams memory newPoolParams = abi.decode(
            params,
            (ISecuritizationPool.NewPoolParams)
        );

        require(
            newPoolParams.minFirstLossCushion < 100 * RATE_SCALING_FACTOR,
            'minFirstLossCushion is greater than 100'
        );
        require(newPoolParams.currency != address(0), 'SecuritizationPool: Invalid currency');

        _setRegistry(registry_);

        // __SecuritizationAccessControl_init_unchained(_msgSender());
        address(this).functionDelegateCall(
            abi.encodeWithSignature('__SecuritizationAccessControl_init_unchained(address)', _msgSender())
        );

        address(this).functionDelegateCall(
            abi.encodeWithSignature(
                '__SecuritizationTGE_init_unchained',
                address(this),
                ISecuritizationTGE.CycleState.INITIATED,
                newPoolParams.currency,
                newPoolParams.minFirstLossCushion
            )
        );

        address(this).functionDelegateCall(
            abi.encodeWithSignature('__SecuritizationPool_init_unchained', address(this), newPoolParams)
        );
    }

    /**
     * @dev Returns the current implementation address.
     */
    function _getImplementation() internal view returns (address) {
        // eip1967.proxy.implementation
        return StorageSlot.getAddressSlot(0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc).value;
    }

    fallback() external payable {
        address impl = _getImplementation();
        address[] memory delegates = SecuritizationPool(payable(impl)).getExtension(msg.sig);

        require(delegates.length == 0, 'Function does not exist.');
        address delegate = delegates[delegates.length - 1];
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

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        // _getModularFactoryStorage()._delegates[bytes]
        if (super.supportsInterface(interfaceId)) return true;

        address[] storage delegates = _getModularFactoryStorage()._delegates[
            bytes4(keccak256('supportsInterface(bytes4)'))
        ];
        for (uint i = 0; i < delegates.length; i++) {
            if (delegates[i].supportsInterface(interfaceId)) return true;
        }

        return false;
    }
}
