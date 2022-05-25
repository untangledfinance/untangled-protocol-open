// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../note-sale/MintedIncreasingInterestTGE.sol';
import '../../base/UntangledBase.sol';
import '../../base/Factory.sol';
import '../../libraries/ConfigHelper.sol';

contract SecuritizationManager is UntangledBase, Factory, ISecuritizationManager {
    using ConfigHelper for Registry;

    function initialize(Registry _registry) public initializer {
        __UntangledBase__init(_msgSender());

        registry = _registry;
    }

    event NewTGECreated(address instanceAddress);
    event NewNotesTokenCreated(address instanceAddress);
    event NewPoolCreated(address instanceAddress);

    //noteSaleAddress, investor, amount, tokenAmount
    event TokensPurchased(address indexed investor, address indexed tgeAddress, uint256 amount, uint256 tokenAmount);

    modifier onlyPoolExisted(ISecuritizationPool pool) {
        require(isExistingPools[address(pool)], 'SecuritizationManager: Pool does not exist');
        _;
    }

    modifier onlyManager(ISecuritizationPool pool) {
        require(
            pool.hasRole(pool.OWNER_ROLE(), _msgSender()),
            'SecuritizationManager: Not the controller of the project'
        );
        _;
    }

    modifier doesSOTExist(ISecuritizationPool pool) {
        require(poolToSOT[address(pool)] == address(0), 'SecuritizationManager: Already exists SOT token');
        _;
    }
    modifier doesJOTExist(ISecuritizationPool pool) {
        require(poolToJOT[address(pool)] == address(0), 'SecuritizationManager: Already exists JOT token');
        _;
    }

    function getPoolsLength() public view returns (uint256) {
        return pools.length;
    }

    function newPoolInstance(address currency, uint32 minFirstLossCushion)
        external
        whenNotPaused
        nonReentrant
        onlyRole(POOL_CREATOR)
        returns (address)
    {
        address poolImplAddress = address(registry.getSecuritizationPool());
        address poolAddress = deployMinimal(poolImplAddress);

        ISecuritizationPool poolInstance = ISecuritizationPool(poolAddress);
        poolInstance.initialize(registry, currency, minFirstLossCushion);
        poolInstance.grantRole(poolInstance.OWNER_ROLE(), _msgSender());
        poolInstance.renounceRole(poolInstance.OWNER_ROLE(), address(this));

        isExistingPools[poolAddress] = true;
        pools.push(poolInstance);

        emit NewPoolCreated(poolAddress);

        return poolAddress;
    }

    function initialTGEForSOT(
        address issuerTokenController,
        ISecuritizationPool pool,
        uint8 saleType,
        uint8 decimalToken,
        bool longSale
    ) external whenNotPaused nonReentrant onlyManager(pool) onlyPoolExisted(pool) doesSOTExist(pool) {
        INoteTokenFactory noteTokenFactory = registry.getNoteTokenFactory();
        address sotToken = noteTokenFactory.createToken(
            address(pool),
            Configuration.NOTE_TOKEN_TYPE.SENIOR,
            decimalToken
        );
        address tgeAddress = registry.getTokenGenerationEventFactory().createNewSaleInstance(
            issuerTokenController,
            address(pool),
            sotToken,
            pool.underlyingCurrency(),
            saleType,
            longSale
        );
        noteTokenFactory.changeMinterRole(sotToken, tgeAddress);

        pool.injectTGEAddress(tgeAddress, sotToken, Configuration.NOTE_TOKEN_TYPE.SENIOR);

        poolToSOT[address(pool)] = sotToken;
        isExistingTGEs[tgeAddress] = true;

        emit NewTGECreated(tgeAddress);
        emit NewNotesTokenCreated(sotToken);
    }

    function initialTGEForJOT(
        address issuerTokenController,
        ISecuritizationPool pool,
        uint8 saleType,
        uint8 decimalToken,
        bool longSale
    ) external whenNotPaused nonReentrant onlyManager(pool) onlyPoolExisted(pool) doesJOTExist(pool) {
        INoteTokenFactory noteTokenFactory = registry.getNoteTokenFactory();
        address jotToken = noteTokenFactory.createToken(
            address(pool),
            Configuration.NOTE_TOKEN_TYPE.JUNIOR,
            decimalToken
        );
        address tgeAddress = registry.getTokenGenerationEventFactory().createNewSaleInstance(
            issuerTokenController,
            address(pool),
            jotToken,
            pool.underlyingCurrency(),
            saleType,
            longSale
        );
        noteTokenFactory.changeMinterRole(jotToken, tgeAddress);

        pool.injectTGEAddress(tgeAddress, jotToken, Configuration.NOTE_TOKEN_TYPE.JUNIOR);

        poolToJOT[address(pool)] = jotToken;
        isExistingTGEs[tgeAddress] = true;

        emit NewTGECreated(tgeAddress);
        emit NewNotesTokenCreated(jotToken);
    }

    function buyTokens(address tgeAddress, uint256 currencyAmount) external whenNotPaused nonReentrant {
        require(isExistingTGEs[tgeAddress], 'SMP: Note sale does not exist');

        uint256 tokenAmount = MintedIncreasingInterestTGE(tgeAddress).buyTokens(
            _msgSender(),
            _msgSender(),
            currencyAmount
        );

        emit TokensPurchased(_msgSender(), tgeAddress, currencyAmount, tokenAmount);
    }

    function pausePool(address poolAddress) external whenNotPaused nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        require(isExistingPools[poolAddress], 'SecuritizationManager: pool does not exist');
        ISecuritizationPool pool = ISecuritizationPool(poolAddress);
        pool.pause();
    }

    function unpausePool(address poolAddress) external whenNotPaused nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        require(isExistingPools[poolAddress], 'SecuritizationManager: pool does not exist');
        ISecuritizationPool pool = ISecuritizationPool(poolAddress);
        pool.unpause();
    }

    function pauseAllPools() external whenNotPaused nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < pools.length; i++) {
            pools[i].pause();
        }
    }

    function unpauseAllPools() external whenNotPaused nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < pools.length; i++) {
            pools[i].unpause();
        }
    }
}
