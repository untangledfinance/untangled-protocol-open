// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {AccessControlEnumerableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol';
import {ERC165Upgradeable} from '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol';
import {IERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol';
import {ERC20BurnableUpgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol';
import {IERC721ReceiverUpgradeable} from '@openzeppelin/contracts-upgradeable/interfaces/IERC721ReceiverUpgradeable.sol';
import {IAccessControlUpgradeable} from '@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol';
import {PausableUpgradeable} from '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import {ReentrancyGuardUpgradeable} from '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';

import {IUntangledERC721} from '../../interfaces/IUntangledERC721.sol';
import {INoteToken} from '../../interfaces/INoteToken.sol';
import {ICrowdSale} from '../note-sale/crowdsale/ICrowdSale.sol';

import {ISecuritizationPool} from './ISecuritizationPool.sol';
import {ISecuritizationPoolValueService} from './ISecuritizationPoolValueService.sol';

import {MintedIncreasingInterestTGE} from '../note-sale/MintedIncreasingInterestTGE.sol';
import {ConfigHelper} from '../../libraries/ConfigHelper.sol';
import {Configuration} from '../../libraries/Configuration.sol';
import {UntangledMath} from '../../libraries/UntangledMath.sol';
import {Registry} from '../../storage/Registry.sol';
import {FinalizableCrowdsale} from './../note-sale/crowdsale/FinalizableCrowdsale.sol';
import {POOL_ADMIN, ORIGINATOR_ROLE, RATE_SCALING_FACTOR} from './types.sol';

import {ISecuritizationLockDistribution} from './ISecuritizationLockDistribution.sol';
import {SecuritizationLockDistribution} from './SecuritizationLockDistribution.sol';
import {SecuritizationTGE} from './SecuritizationTGE.sol';
import {ISecuritizationTGE} from './ISecuritizationTGE.sol';
import {RegistryInjection} from './RegistryInjection.sol';

import {SecuritizationAccessControl} from './SecuritizationAccessControl.sol';
import {ISecuritizationAccessControl} from './ISecuritizationAccessControl.sol';

import {RiskScore} from './base/types.sol';

import {ISecuritizationPoolStorage} from './ISecuritizationPoolStorage.sol';
import {SecuritizationPoolAsset} from './SecuritizationPoolAsset.sol';
import {SecuritizationPoolStorage} from './SecuritizationPoolStorage.sol';
import {AddressUpgradeable} from '@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol';

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {ISecuritizationPoolExtension} from './ISecuritizationPoolExtension.sol';

import 'hardhat/console.sol';

/**
 * @title Untangled's SecuritizationPool contract
 * @notice Main entry point for senior LPs (a.k.a. capital providers)
 *  Automatically invests across borrower pools using an adjustable strategy.
 * @author Untangled Team
 */
// is
// RegistryInjection,
// SecuritizationAccessControl,
// SecuritizationPoolStorage,
// SecuritizationTGE,
// SecuritizationPoolAsset,
// SecuritizationLockDistribution
contract SecuritizationPool is Initializable, RegistryInjection {
    using ConfigHelper for Registry;
    using AddressUpgradeable for address;

    address public original;

    address[] public extensions;
    mapping(bytes4 => address) public delegates;
    mapping(address => bytes4[]) public extensionSignatures;

    function extensionsLength() public view returns (uint256) {
        return extensions.length;
    }

    modifier onlyCallInOriginal() {
        require(original == address(this), 'Only call in original contract');
        _;
    }

    constructor() {
        original = address(this); // default original
    }

    function registerExtension(address ext) public onlyCallInOriginal {
        _registerExtension(ext);
    }

    function _registerExtension(address ext) internal {
        extensions.push(ext);

        bytes4[] memory signatures = ISecuritizationPoolExtension(ext).getFunctionSignatures();
        for (uint i = 0; i < signatures.length; i++) {
            delegates[signatures[i]] = ext;
        }

        extensionSignatures[ext] = signatures;
    }

    function _installExtension(address ext, bytes memory data) internal {
        ext.functionDelegateCall(abi.encodeWithSelector(0x326cd970, data));
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
        address poolImpl = address(registry_.getSecuritizationPool());
        require(poolImpl != address(0), 'SecuritizationPool: No pool implementation');
        original = poolImpl;

        ISecuritizationPoolStorage.NewPoolParams memory newPoolParams = abi.decode(
            params,
            (ISecuritizationPoolStorage.NewPoolParams)
        );

        require(
            newPoolParams.minFirstLossCushion < 100 * RATE_SCALING_FACTOR,
            'minFirstLossCushion is greater than 100'
        );
        require(newPoolParams.currency != address(0), 'SecuritizationPool: Invalid currency');

        // __ReentrancyGuard_init_unchained();

        // __SecuritizationAccessControl_init_unchained(_msgSender());
        // // __UntangledBase__init(_msgSender());

        // // _setRoleAdmin(ORIGINATOR_ROLE, OWNER_ROLE);
        // _setRegistry(registry_);

        // __SecuritizationTGE_init_unchained(
        //     address(this),
        //     CycleState.INITIATED,
        //     newPoolParams.currency,
        //     newPoolParams.minFirstLossCushion
        // );

        // __SecuritizationPoolAsset_init_unchained(newPoolParams);

        _setRegistry(registry_);

        uint256 exLength = SecuritizationPool(payable(original)).extensionsLength();

        for (uint i = 0; i < exLength; ++i) {
            address ext = SecuritizationPool(payable(original)).extensions(i);
            _installExtension(ext, params);
        }
    }

    fallback() external payable {
        address delegate = SecuritizationPool(payable(original)).delegates(msg.sig);

        require(delegate != address(0), string(abi.encodePacked('No delegate for ', msg.sig)));

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

    // function supportsInterface(
    //     bytes4 interfaceId
    // )
    //     public
    //     view
    //     virtual
    //     override(
    //         SecuritizationPoolAsset,
    //         SecuritizationTGE,
    //         SecuritizationLockDistribution,
    //         SecuritizationAccessControl,
    //         SecuritizationPoolStorage
    //     )
    //     returns (bool)
    // {
    //     return
    //         SecuritizationPoolStorage.supportsInterface(interfaceId) ||
    //         SecuritizationPoolAsset.supportsInterface(interfaceId) ||
    //         SecuritizationLockDistribution.supportsInterface(interfaceId) ||
    //         SecuritizationTGE.supportsInterface(interfaceId);
    // }

    // function pause() public override(SecuritizationLockDistribution, SecuritizationPoolAsset, SecuritizationTGE) {
    //     SecuritizationTGE.pause();
    // }

    // function unpause() public override(SecuritizationLockDistribution, SecuritizationPoolAsset, SecuritizationTGE) {
    //     SecuritizationTGE.unpause();
    // }
}
