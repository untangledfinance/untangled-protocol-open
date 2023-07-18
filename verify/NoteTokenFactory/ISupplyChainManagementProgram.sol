// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './Registry.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';

abstract contract ISupplyChainManagementProgram is Initializable, PausableUpgradeable, AccessControlEnumerableUpgradeable {
    Registry public registry;

    bytes32 public constant PRICE_FEED_ROLE = keccak256('PRICE_FEED_ROLE');
    bytes32 public constant OWNER_ROLE = keccak256('OWNER_ROLE');

    mapping(uint256 => CollateralProject) public collateralProjects;
    mapping(uint256 => bool) public isExistingProjects;

    mapping(uint256 => mapping(address => bool)) public projectToLenders;
    mapping(uint256 => mapping(address => bool)) public projectToTraders;
    mapping(uint256 => mapping(address => bool)) public projectToExecutors;
    mapping(address => bool) public isExistingManager;

    //Id of project -> id of project-commodity => existed
    mapping(uint256 => mapping(uint256 => bool)) public projectToExistedProjectCommodity;
    //Id of project -> bytes32 of movement
    mapping(uint256 => mapping(bytes32 => Movement)) public projectToMovements;
    mapping(uint256 => mapping(bytes32 => bool)) public projectToExistedMovements;

    //Id of project-commodity- => price
    mapping(uint256 => uint256) public projectCommodityToPrice;
    //Id of project-commodity => list agreements id
    mapping(uint256 => bytes32[]) public projectCommodityToAgreements;
    //Id of project-commodity -> commodity symbol hash
    mapping(uint256 => bytes32) public projectCommodityToCommodity;
    //Id of project-commodity -> project id
    mapping(uint256 => uint256) public projectCommodityToProject;

    struct CollateralProject {
        address managerAddress;
        address projectWallet;
        bytes32 companyHash;
    }

    enum MovementState {INITIATED, APPROVED, EXECUTED}
    enum MovementType {UNKNOWN, DEPOSIT, WITHDRAW}

    struct Movement {
        uint256 projectCommodityId;
        MovementType movementType;
        MovementState state;
        uint quantity;
        address initiator;
        address approver;
        address executor;
    }

    function initialize(
        Registry _registry
    ) public virtual;

    //************  */
    // EXTERNAL
    //************  *
    // Create new CMA project
    function newProject(
        uint256 projectId,
        string memory companyId,
        address projectWallet
    ) public virtual;

    function updateCompanyId(uint256 projectId, string memory companyId) public virtual;

    function addCommodity(
        uint256 projectId,
        uint256 projectCommodityId,
        string memory commodity,
        uint256 initBalance
    ) public virtual;

    // Add Trader for CMA project
    function addTrader(uint256 projectId, address trader)
    public virtual;

    // Add Lender for CMA project
    function addLender(uint256 projectId, address lender)
    public virtual;

    // Add Executor for CMA project
    function addExecutor(uint256 projectId, address executor)
    public virtual;

    // Remove Trader for CMA project
    /** @dev NOTE: delete array element but still occupy storage space */
    function removeTrader(uint256 projectId, address trader)
    public virtual;

    // Remove Lender for CMA project
    function removeLender(uint256 projectId, address lender)
    public virtual;

    // Remove Executor for CMA project
    function removeExecutor(uint256 projectId, address executor)
    public virtual;

    function isTrader(uint256 projectId, address account) public view virtual returns (bool);

    function isLender(uint256 projectId, address account) public view virtual returns (bool);

    function isExecutor(uint256 projectId, address account) public view virtual returns (bool);

    function initMovement(
        string memory movementId,
        uint256 projectId,
        uint256 projectCommodityId,
        uint8 _movementType
    ) public virtual;

    function approveMovement(
        string memory movementId,
        uint256 projectId
    ) public virtual;

    function executeMovement(
        string memory movementId,
        uint256 projectId,
        uint _quantity
    ) public virtual;

    function updateStateMovement(
        string memory movementId,
        uint256 projectId,
        MovementState _movementState,
        uint _quantity,
        address caller
    ) public virtual;

    function isProjectExisting(uint256 projectId) public view virtual returns (bool);

    /**
    * @dev NOTE: memory & public is not recommeneded for function which have input param is arrays, calldata & external function instead
     */
    function bulkInsertCompletedMovement(
        bytes32[] memory movementIdsHashes,
        uint256[] memory projectIds,
        uint256[] memory projectCommodityIds,
        uint8[] memory movementTypes,
        address[] memory traders,
        address[] memory executors,
        uint[] memory quantities
    ) public virtual;

    function addExistedBalance(
        uint256 projectId,
        uint256 projectCommodityId,
        address trader,
        uint quantity
    ) public virtual;

    function removeExistedBalance(
        uint256 projectId,
        uint256 projectCommodityId,
        address trader,
        uint quantity
    ) public virtual;

    function getCommodityPrice(uint256 projectCommodityId) public view virtual returns (uint256);

    function updateCommodityPrice(uint256 projectCommodityId, uint256 price) public virtual;

    function insertAgreementToCommodity(uint256 projectCommodityId, bytes32 agreementId) public virtual;

    function removeAgreementFromCommodity(uint256 projectCommodityId, bytes32 agreementId) public virtual;

    function getAgreementsOfProjectCommodity(uint256 projectCommodityId) public view virtual returns (bytes32[] memory);

/*
    function getProjectDetail(uint256 projectId) public view virtual
    returns (address managerAddress, address projectWallet, bytes32 companyHash);
*/

/*
    function getMovementDetail(string memory movementId, uint256 projectId) public view virtual
    returns (
        uint256 projectCommodityId,
        MovementType movementType,
        MovementState state,
        uint256 quantity,
        address initiator,
        address approver,
        address executor
    );
*/

/*
    function getProjectCommodityDetail(uint256 projectCommodityId) public view virtual
    returns (
        uint256 projectId,
        uint256 price,
        bytes32 commoditySymbol
    );
*/

}