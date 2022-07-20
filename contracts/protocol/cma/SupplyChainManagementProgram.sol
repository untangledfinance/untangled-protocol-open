// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../interfaces/ISupplyChainManagementProgram.sol";
import "../../libraries/ConfigHelper.sol";
import "../loan/inventory/InventoryLoanRegistry.sol";

contract SupplyChainManagementProgram is ISupplyChainManagementProgram {
    using ConfigHelper for Registry;

    /** CONSTRUCTOR */
    function initialize(
        Registry _registry
    ) public override initializer {
        __UntangledBase__init(_msgSender());
        _setRoleAdmin(PRICE_FEED_ROLE, OWNER_ROLE);
        registry = _registry;
    }

    function _isMovementExisting(
        uint256 projectId,
        string memory movementId
    ) internal view returns (bool) {
        bytes32 identifyHashMovement = keccak256(abi.encodePacked(movementId));
        return projectToExistedMovements[projectId][identifyHashMovement];
    }

    function _isMovementExisting(
        uint256 projectId,
        bytes32 movementHash
    ) internal view returns (bool) {
        return projectToExistedMovements[projectId][movementHash];
    }

    function _isCollateralManager(uint256 projectId, address manager) internal view returns (bool) {
        return collateralProjects[projectId].managerAddress == manager;
    }

    modifier onlyCollateralManager(uint256 projectId) {
        require(_isCollateralManager(projectId, msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Collateral Manager: caller is not the manager of the project");
        _;
    }

    modifier onlyTrader(uint256 projectId) {
        require(projectToTraders[projectId][msg.sender], "Collateral Project: caller is not the trader of the project");
        _;
    }

    modifier onlyProjectExisted(uint256 projectId) {
        require(isExistingProjects[projectId], "Project does not exists.");
        _;
    }

    modifier onlyPriceFeedManager() {
        require(
            isExistingManager[msg.sender] || hasRole(PRICE_FEED_ROLE, msg.sender),
            "SupplyChainManagementProgram: Not authorized to update price"
        );
        _;
    }

    //************  */
    // EXTERNAL
    //************  *
    // Create new CMA project
    function newProject(
        uint256 projectId,
        string memory companyId,
        address projectWallet
    ) public override {
        // 1. Create new multisignature wallet as tokens recepient of this CMA project
        // 2. Record project information to metadata of new Non-Fungile Token
        // 3. Mint initBalance quantity of Fungible Token and credit to Multisign Wallet above
        require(!isExistingProjects[projectId], "Project already existed");

        collateralProjects[projectId] = CollateralProject({
        managerAddress : msg.sender,
        projectWallet : projectWallet,
        companyHash : keccak256(abi.encodePacked(companyId))
        });
        isExistingProjects[projectId] = true;
        isExistingManager[msg.sender] = true;
    }

    function updateCompanyId(uint256 projectId, string memory companyId) public override
    onlyProjectExisted(projectId)
    onlyCollateralManager(projectId){

        CollateralProject memory collateralProject = collateralProjects[projectId];
        collateralProject.companyHash = keccak256(abi.encodePacked(companyId));

        collateralProjects[projectId] = collateralProject;

    }

    function addCommodity (
        uint256 projectId,
        uint256 projectCommodityId,
        string memory commodity,
        uint256 initBalance
    ) public override
    onlyProjectExisted(projectId)
    onlyCollateralManager(projectId) {
        require(!projectToExistedProjectCommodity[projectId][projectCommodityId], "Project commodity already existed.");

        projectCommodityToCommodity[projectCommodityId] = keccak256(abi.encodePacked(commodity));
        projectCommodityToProject[projectCommodityId] = projectId;
        projectToExistedProjectCommodity[projectId][projectCommodityId] = true;

        address walletAddress = collateralProjects[projectId].projectWallet;

        bytes  memory data;
        registry.getCollateralManagementToken().mint(walletAddress, projectCommodityId, initBalance, data);
    }

    // Add Trader for CMA project
    function addTrader(uint256 projectId, address trader)
    public override onlyProjectExisted(projectId)
    onlyCollateralManager(projectId) {
        require(!projectToTraders[projectId][trader], "Trader already existed.");
        projectToTraders[projectId][trader] = true;
    }

    // Add Lender for CMA project
    function addLender(uint256 projectId, address lender)
    public
    override
    onlyProjectExisted(projectId)
    onlyCollateralManager(projectId) {
        require(!projectToLenders[projectId][lender], "Lender already existed.");
        projectToLenders[projectId][lender] = true;
    }

    // Add Executor for CMA project
    function addExecutor(uint256 projectId, address executor)
    public override onlyProjectExisted(projectId)
    onlyCollateralManager(projectId) {
        require(!projectToExecutors[projectId][executor], "Executor already existed.");
        projectToExecutors[projectId][executor] = true;
    }

    // Remove Trader for CMA project
    /** @dev NOTE: delete array element but still occupy storage space */
    function removeTrader(uint256 projectId, address trader)
    public override onlyProjectExisted(projectId)
    onlyCollateralManager(projectId) {
        require(projectToTraders[projectId][trader], "Trader does not exist.");
        delete projectToTraders[projectId][trader];
    }

    // Remove Lender for CMA project
    function removeLender(uint256 projectId, address lender)
    public
    override
    onlyProjectExisted(projectId)
    onlyCollateralManager(projectId) {
        require(projectToLenders[projectId][lender], "Lender does not exist.");
        delete projectToLenders[projectId][lender];
    }

    // Remove Executor for CMA project
    function removeExecutor(uint256 projectId, address executor)
    public override
    onlyProjectExisted(projectId)
    onlyCollateralManager(projectId) {
        require(projectToExecutors[projectId][executor], "Executor does not exist.");
        delete projectToExecutors[projectId][executor];
    }

    function isTrader(uint256 projectId, address account) public override view returns (bool) {
        return projectToTraders[projectId][account];
    }

    function isLender(uint256 projectId, address account) public override view returns (bool) {
        return projectToLenders[projectId][account];
    }

    function isExecutor(uint256 projectId, address account) public override view returns (bool) {
        return projectToExecutors[projectId][account];
    }

    function initMovement(
        string memory movementId,
        uint256 projectId,
        uint256 projectCommodityId,
        uint8 _movementType
    ) public override onlyProjectExisted(projectId) onlyTrader(projectId) {
        require(!_isMovementExisting(projectId, movementId), "Movement already existed.");
        require(projectToExistedProjectCommodity[projectId][projectCommodityId], "Project commodity not existed.");
        require(_movementType != uint8(MovementType.UNKNOWN), "Unknown movement type.");

        bytes32 identifyHashMovement = keccak256(abi.encodePacked(movementId));

        Movement memory movement = Movement({
        projectCommodityId: projectCommodityId,
        movementType: MovementType.UNKNOWN,
        state: MovementState.INITIATED,
        quantity: 0,
        initiator: msg.sender,
        approver: address(0x0),
        executor: address(0x0)
        });

        if (_movementType == uint8(MovementType.DEPOSIT)) {
            movement.movementType = MovementType.DEPOSIT;

        } else if (_movementType == uint8(MovementType.WITHDRAW)) {
            movement.movementType = MovementType.WITHDRAW;
        }

        projectToMovements[projectId][identifyHashMovement] = movement;
        projectToExistedMovements[projectId][identifyHashMovement] = true;
    }

    function approveMovement(
        string memory movementId,
        uint256 projectId
    ) public override {
        updateStateMovement(
            movementId,
            projectId,
            MovementState.APPROVED,
            0,
            msg.sender
        );
    }

    function executeMovement(
        string memory movementId,
        uint256 projectId,
        uint _quantity
    ) public override {
        updateStateMovement(
            movementId,
            projectId,
            MovementState.EXECUTED,
            _quantity,
            msg.sender
        );
    }

    function updateStateMovement(
        string memory movementId,
        uint256 projectId,
        MovementState _movementState,
        uint _quantity,
        address caller
    ) public override onlyProjectExisted(projectId) {
        require(_isMovementExisting(projectId, movementId), "Movement does not exist.");

        bytes32 identifyHashMovement = keccak256(abi.encodePacked(movementId));

        Movement memory movement = projectToMovements[projectId][identifyHashMovement];

        if (_movementState == MovementState.EXECUTED) {
            require(isExecutor(projectId, caller), "Collateral Manager: caller is not the executor of the project");
            require(movement.state == MovementState.INITIATED, "Execute Movement: state invalid");
            require(_quantity > 0, "Invalid movement quantity.");

            if(movement.movementType == MovementType.WITHDRAW) {
                _doWithdraw(movement.initiator, movement.projectCommodityId, _quantity);
            } else if (movement.movementType == MovementType.DEPOSIT) {
                _doDeposit(movement.initiator, movement.projectCommodityId, _quantity);
            }

            movement.quantity = _quantity;
            movement.state = MovementState.EXECUTED;
            movement.executor = caller;
        }

        projectToMovements[projectId][identifyHashMovement] = movement;
    }

    // Trader do withdraw
    function _doWithdraw(address trader, uint256 projectCommodityId, uint quantity) internal {
        registry.getCollateralManagementToken().burn(trader, projectCommodityId, quantity);
    }

    // Trader do Deposit
    function _doDeposit(address trader, uint256 projectCommodityId, uint quantity) internal {
        registry.getCollateralManagementToken().mint(trader, projectCommodityId, quantity, "");
    }

    function isProjectExisting(uint256 projectId) public override view returns (bool) {
        return isExistingProjects[projectId];
    }

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
    ) public override {
        for (uint256 i = 0; i < movementIdsHashes.length; ++i) {
            require(isExistingProjects[projectIds[i]], "Project does not exists.");
            require(!_isMovementExisting(projectIds[i], movementIdsHashes[i]), "Movement already existed.");
            require(projectToExistedProjectCommodity[projectIds[i]][projectCommodityIds[i]], "Project commodity not existed.");
            require(movementTypes[i] != uint8(MovementType.UNKNOWN), "Unknown movement type.");
            require(quantities[i] != 0, "Invalid movement quantity.");
            require(_isCollateralManager(projectIds[i], msg.sender), "Collateral Manager: caller is not the manager of the project");
            require(isTrader(projectIds[i], traders[i]), "Collateral Project: not the trader of the project");
            require(isExecutor(projectIds[i], executors[i]), "Collateral Manager: not the executor of the project");

            Movement memory movement = Movement({
            projectCommodityId: projectCommodityIds[i],
            movementType: MovementType.UNKNOWN,
            state: MovementState.EXECUTED,
            quantity: quantities[i],
            initiator: traders[i],
            approver: address(0x0),
            executor: executors[i]
            });

            if (movementTypes[i] == uint8(MovementType.DEPOSIT)) {
                _doDeposit(traders[i], movement.projectCommodityId, movement.quantity);
                movement.movementType = MovementType.DEPOSIT;

            } else if (movementTypes[i] == uint8(MovementType.WITHDRAW)) {
                _doWithdraw(traders[i], movement.projectCommodityId, movement.quantity);
                movement.movementType = MovementType.WITHDRAW;
            }

            projectToMovements[projectIds[i]][movementIdsHashes[i]] = movement;
            projectToExistedMovements[projectIds[i]][movementIdsHashes[i]] = true;
        }
    }

    function addExistedBalance(
        uint256 projectId,
        uint256 projectCommodityId,
        address trader,
        uint quantity
    ) public override onlyProjectExisted(projectId) onlyCollateralManager(projectId) {
        require(projectToExistedProjectCommodity[projectId][projectCommodityId], "Project commodity not existed.");
        require(isTrader(projectId, trader), "Collateral Project: trader is not the trader of the project");
        require(quantity != 0, "Invalid quantity.");

        registry.getCollateralManagementToken().mint(trader, projectCommodityId, quantity, "");
    }

    function removeExistedBalance(
        uint256 projectId,
        uint256 projectCommodityId,
        address trader,
        uint quantity
    ) public override onlyProjectExisted(projectId) onlyCollateralManager(projectId) {
        require(projectToExistedProjectCommodity[projectId][projectCommodityId], "Project commodity not existed.");
        require(isTrader(projectId, trader), "Collateral Project: trader is not the trader of the project");
        require(quantity != 0, "Invalid quantity.");

        registry.getCollateralManagementToken().burn(trader, projectCommodityId, quantity);
    }

    function getCommodityPrice(uint256 projectCommodityId) public override view returns (uint256) {
        require(projectCommodityToCommodity[projectCommodityId] != bytes32(0), "SupplyChainManagementProgram: project commodity not existed");
        return projectCommodityToPrice[projectCommodityId];
    }

    function updateCommodityPrice(uint256 projectCommodityId, uint256 price) public override onlyPriceFeedManager() {
        require(price > 0, "SupplyChainManagementProgram: price must greater than 0");
        require(projectCommodityToCommodity[projectCommodityId] != bytes32(0), "SupplyChainManagementProgram: project commodity not existed");

        if (projectCommodityToPrice[projectCommodityId] != price) {
            projectCommodityToPrice[projectCommodityId] = price;
            InventoryLoanRegistry debtRegistry = registry.getInventoryLoanRegistry();

            if (projectCommodityToAgreements[projectCommodityId].length > 0) {
                for (uint i = 0; i < projectCommodityToAgreements[projectCommodityId].length; ++i) {
                    debtRegistry.selfEvaluateCollateralRatio(projectCommodityToAgreements[projectCommodityId][i]);
                }
            }
        }
    }

    function insertAgreementToCommodity(uint256 projectCommodityId, bytes32 agreementId) public override {
        require(msg.sender == address(registry.getInventoryLoanKernel()), "SupplyChainManagementProgram: not authorized to add agreement");
        require(projectCommodityToCommodity[projectCommodityId] != bytes32(0), "SupplyChainManagementProgram: project commodity not existed");

        projectCommodityToAgreements[projectCommodityId].push(agreementId);
    }

    function removeAgreementFromCommodity(uint256 projectCommodityId, bytes32 agreementId) public override onlyRole(OWNER_ROLE) {
//        require(isOwner() || _isAuthorizedContract(msg.sender), "SupplyChainManagementProgram: not authorized to remove agreement");
        require(projectCommodityToCommodity[projectCommodityId] != bytes32(0), "SupplyChainManagementProgram: project commodity not existed");

        if (projectCommodityToAgreements[projectCommodityId].length > 0) {
            for (uint i = 0; i < projectCommodityToAgreements[projectCommodityId].length; ++i) {
                if (projectCommodityToAgreements[projectCommodityId][i] == agreementId) {

                    // Remove i element from projectCommodityToAgreements[projectCommodityId]
                    for (uint index = i; index<projectCommodityToAgreements[projectCommodityId].length-1; index++){
                        projectCommodityToAgreements[projectCommodityId][index] = projectCommodityToAgreements[projectCommodityId][index+1];
                    }
                    projectCommodityToAgreements[projectCommodityId].pop();
                    break;
                }
            }
        }
    }

    function getAgreementsOfProjectCommodity(uint256 projectCommodityId) public override view returns (bytes32[] memory) {
        return projectCommodityToAgreements[projectCommodityId];
    }
/*
    function getProjectDetail(uint256 projectId) public override view onlyProjectExisted(projectId)
    returns (address managerAddress, address projectWallet, bytes32 companyHash) {
        return (collateralProjects[projectId].managerAddress, collateralProjects[projectId].projectWallet, collateralProjects[projectId].companyHash);
    }

    function getMovementDetail(string memory movementId, uint256 projectId)
    public
    override
    view
    onlyProjectExisted(projectId)
    returns (
        uint256 projectCommodityId,
        MovementType movementType,
        MovementState state,
        uint256 quantity,
        address initiator,
        address approver,
        address executor
    )
    {
        require(
            _isMovementExisting(projectId, movementId),
            'Movement does not exist.'
        );
        bytes32 identifyHashMovement = keccak256(abi.encodePacked(movementId));

        Movement memory movement = projectToMovements[projectId][identifyHashMovement];
        return (
        movement.projectCommodityId,
        movement.movementType,
        movement.state,
        movement.quantity,
        movement.initiator,
        movement.approver,
        movement.executor
        );
    }
*/

/*
    function getProjectCommodityDetail(uint256 projectCommodityId) public override view
    returns (
        uint256 projectId,
        uint256 price,
        bytes32 commoditySymbol
    ) {
        return (
        projectCommodityToProject[projectCommodityId],
        projectCommodityToPrice[projectCommodityId],
        projectCommodityToCommodity[projectCommodityId]
        );
    }
*/

}