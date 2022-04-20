// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../../interfaces/IMintedTokenGenerationEvent.sol';
import '../../base/UntangledBase.sol';
import '../../base/Factory.sol';
import '../../storage/Registry.sol';
import '../../libraries/ConfigHelper.sol';

contract SecuritizationManager is UntangledBase, Factory, ISecuritizationManager {
    using ConfigHelper for Registry;

    Registry public registry;

    function initialize(Registry _registry) public initializer {
        __UntangledBase__init(address(this));

        registry = _registry;
    }

    event NewTGECreated(address instanceAddress);
    event NewNotesTokenCreated(address instanceAddress);
    event NewPoolCreated(address instanceAddress);

    mapping(address => bool) public isExistingPools;
    ISecuritizationPool[] public pools;

    mapping(address => address) public poolToSOT;
    mapping(address => address) public poolToJOT;

    mapping(address => bool) public isExistingTGEs;

    //noteSaleAddress, investor, amount, tokenAmount
    event TokensPurchased(address indexed investor, address indexed tgeAddress, uint256 amount, uint256 tokenAmount);

    modifier onlyPoolExisted(ISecuritizationPool pool) {
        require(isExistingPools[address(pool)], 'Pool does not exist');
        _;
    }

    modifier onlyManager(ISecuritizationPool pool) {
        require(pool.hasRole(pool.OWNER_ROLE(), _msgSender()), 'Not the controller of the project');
        _;
    }

    modifier doesSOTExist(ISecuritizationPool pool) {
        require(poolToSOT[address(pool)] == address(0), 'Already exists SOT token');
        _;
    }
    modifier doesJOTExist(ISecuritizationPool pool) {
        require(poolToJOT[address(pool)] == address(0), 'Already exists JOT token');
        _;
    }

    function getPoolsLength() public view returns (uint256) {
        return pools.length;
    }

    function isExistingNoteToken(address pool, address noteToken) external view returns (bool) {
        return isExistingPools[pool] && (poolToSOT[pool] == noteToken || poolToJOT[pool] == noteToken);
    }

    function newPoolInstance(address currency, uint32 minFirstLossCushion)
        external
        whenNotPaused
        nonReentrant
        returns (address)
    {
        address poolImplAddress = address(registry.getSecuritizationPool());
        address poolAddress = deployMinimal(poolImplAddress);

        ISecuritizationPool poolInstance = ISecuritizationPool(poolAddress);
        poolInstance.initialize(_msgSender(), registry, currency, minFirstLossCushion);

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
        address sotToken = noteTokenFactory.createSOTToken(
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
        noteTokenFactory.changeTokenController(sotToken, tgeAddress);

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
        address jotToken = noteTokenFactory.createJOTToken(
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
        noteTokenFactory.changeTokenController(jotToken, tgeAddress);

        pool.injectTGEAddress(tgeAddress, jotToken, Configuration.NOTE_TOKEN_TYPE.JUNIOR);

        poolToJOT[address(pool)] = jotToken;
        isExistingTGEs[tgeAddress] = true;

        emit NewTGECreated(tgeAddress);
        emit NewNotesTokenCreated(jotToken);
    }

    function buyTokens(address tgeAddress, uint256 currencyAmount) external whenNotPaused nonReentrant {
        require(isExistingTGEs[tgeAddress], 'SMP: Note sale does not exist');

        uint256 tokenAmount = IMintedTokenGenerationEvent(tgeAddress).buyTokens(
            _msgSender(),
            _msgSender(),
            currencyAmount
        );

        emit TokensPurchased(_msgSender(), tgeAddress, currencyAmount, tokenAmount);
    }
}
