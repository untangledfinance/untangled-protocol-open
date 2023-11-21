// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {AccessControlEnumerableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol';
import {ERC165Upgradeable} from '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol';
import {IERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol';
import {ERC20BurnableUpgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol';
import {IERC721ReceiverUpgradeable} from '@openzeppelin/contracts-upgradeable/interfaces/IERC721ReceiverUpgradeable.sol';
import {IAccessControlUpgradeable} from '@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol';
import {PausableUpgradeable} from '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';

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

/**
 * @title Untangled's SecuritizationPool contract
 * @notice Main entry point for senior LPs (a.k.a. capital providers)
 *  Automatically invests across borrower pools using an adjustable strategy.
 * @author Untangled Team
 */
interface ISecuritizationPoolExtension {
    function getFunctionSignatures() external view returns (bytes4[] memory);

    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
