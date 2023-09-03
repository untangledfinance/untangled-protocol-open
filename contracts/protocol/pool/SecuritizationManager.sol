// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../note-sale/MintedIncreasingInterestTGE.sol';
import '../../base/UntangledBase.sol';
import '../../base/Factory.sol';
import '../../libraries/ConfigHelper.sol';
import "../../interfaces/IRequiresUID.sol";

contract SecuritizationManager is UntangledBase, Factory, ISecuritizationManager, IRequiresUID {
    using ConfigHelper for Registry;
    uint256[] public allowedUIDTypes;

    struct NewRoundSaleParam {
        uint256 openingTime;
        uint256 closingTime;
        uint256 rate;
        uint256 cap;
    }

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
        uint8[] memory saleTypeAndDecimal,
        bool longSale,
        string memory ticker
    ) public whenNotPaused nonReentrant onlyManager(pool) onlyPoolExisted(pool) doesSOTExist(pool) returns (address) {
        INoteTokenFactory noteTokenFactory = registry.getNoteTokenFactory();
        require(address(noteTokenFactory) != address(0), 'Note Token Factory was not registered');
        require(address(registry.getTokenGenerationEventFactory()) != address(0), 'TGE Factory was not registered');
        address sotToken = noteTokenFactory.createToken(
            address(pool),
            Configuration.NOTE_TOKEN_TYPE.SENIOR,
            saleTypeAndDecimal[1],
            ticker
        );
        address tgeAddress = registry.getTokenGenerationEventFactory().createNewSaleInstance(
            issuerTokenController,
            address(pool),
            sotToken,
            pool.underlyingCurrency(),
            saleTypeAndDecimal[0],
            longSale
        );
        noteTokenFactory.changeMinterRole(sotToken, tgeAddress);

        pool.injectTGEAddress(tgeAddress, sotToken, Configuration.NOTE_TOKEN_TYPE.SENIOR);

        poolToSOT[address(pool)] = sotToken;
        isExistingTGEs[tgeAddress] = true;

        emit NewTGECreated(tgeAddress);
        emit NewNotesTokenCreated(sotToken);
        return tgeAddress;
    }

    /// @notice Sets up the token generation event (TGE) for the senior tranche (SOT) of a securitization pool with additional configuration parameters
    /// @param issuerTokenController Who acts as owner of note sale
    /// @param pool SecuritizationPool address where this sale belongs to
    /// @param saleTypeAndDecimal Contains sale type parameter and decimal value of note token
    /// @param longSale Define this sale is long sale. Default true
    /// @param _initialInterest For SOT auction token sale. An initial interest rate is defined
    /// @param _finalInterest For SOT auction token sale. This is the largest interest rate
    /// @param _timeInterval For SOT auction token sale. After every time interval, the current interest rate will increase from initial interest value
    /// @param _amountChangeEachInterval For SOT auction token sale. After every time interval, the current interest rate will increase a value of amountChangeEachInterval
    /// @param saleParam Some parameters for new round token sale. Ex: openingTime, closeTime, totalCap...
    /// @param ticker Prefix for note token symbol name. Ex: Saff_SOT
    function setUpTGEForSOT(
        address issuerTokenController,
        ISecuritizationPool pool,
        uint8[] memory saleTypeAndDecimal,
        bool longSale,
        uint256 additionalCap,
        uint32 _initialInterest,
        uint32 _finalInterest,
        uint32 _timeInterval,
        uint32 _amountChangeEachInterval,
        NewRoundSaleParam memory saleParam,
        string calldata ticker
    ) public {
        address tgeAddress = initialTGEForSOT(issuerTokenController, pool, saleTypeAndDecimal, longSale, ticker);
        MintedIncreasingInterestTGE tge = MintedIncreasingInterestTGE(tgeAddress);
        tge.addFunding(additionalCap);
        tge.setInterestRange(_initialInterest, _finalInterest, _timeInterval, _amountChangeEachInterval);
        tge.startNewRoundSale(saleParam.openingTime, saleParam.closingTime, saleParam.rate, saleParam.cap);
    }

    /// @notice sets up the token generation event (TGE) for the junior tranche (JOT) of a securitization pool with additional configuration parameters
    /// @param issuerTokenController Who acts as owner of note sale
    /// @param pool SecuritizationPool address where this sale belongs to
    /// @param saleTypeAndDecimal Contains sale type parameter and decimal value of note token
    /// @param longSale Define this sale is long sale. Default true
    /// @param saleParam Some parameters for new round token sale. Ex: openingTime, closeTime, totalCap...
    /// @param ticker Prefix for note token symbol name. Ex: Saff_JOT
    function setUpTGEForJOT(
        address issuerTokenController,
        ISecuritizationPool pool,
        uint8[] memory saleTypeAndDecimal,
        bool longSale,
        uint256 additionalCap,
        NewRoundSaleParam memory saleParam,
        string calldata ticker
    ) public {
        address tgeAddress = initialTGEForJOT(issuerTokenController, pool, saleTypeAndDecimal, longSale, ticker);
        MintedNormalTGE tge = MintedNormalTGE(tgeAddress);
        tge.addFunding(additionalCap);
        tge.startNewRoundSale(saleParam.openingTime, saleParam.closingTime, saleParam.rate, saleParam.cap);
    }

    function initialTGEForJOT(
        address issuerTokenController,
        ISecuritizationPool pool,
        uint8[] memory saleTypeAndDecimal,
        bool longSale,
        string memory ticker
    ) public whenNotPaused nonReentrant onlyManager(pool) onlyPoolExisted(pool) doesJOTExist(pool) returns (address) {
        INoteTokenFactory noteTokenFactory = registry.getNoteTokenFactory();
        address jotToken = noteTokenFactory.createToken(
            address(pool),
            Configuration.NOTE_TOKEN_TYPE.JUNIOR,
            saleTypeAndDecimal[1],
            ticker
        );
        address tgeAddress = registry.getTokenGenerationEventFactory().createNewSaleInstance(
            issuerTokenController,
            address(pool),
            jotToken,
            pool.underlyingCurrency(),
            saleTypeAndDecimal[0],
            longSale
        );
        noteTokenFactory.changeMinterRole(jotToken, tgeAddress);

        pool.injectTGEAddress(tgeAddress, jotToken, Configuration.NOTE_TOKEN_TYPE.JUNIOR);

        poolToJOT[address(pool)] = jotToken;
        isExistingTGEs[tgeAddress] = true;

        emit NewTGECreated(tgeAddress);
        emit NewNotesTokenCreated(jotToken);
        return tgeAddress;
    }

    function buyTokens(address tgeAddress, uint256 currencyAmount) external whenNotPaused nonReentrant {
        require(isExistingTGEs[tgeAddress], 'SMP: Note sale does not exist');
        require(hasAllowedUID(_msgSender()), 'Unauthorized. Must have correct UID');

        MintedIncreasingInterestTGE tge = MintedIncreasingInterestTGE(tgeAddress);
        uint256 tokenAmount = tge.buyTokens(_msgSender(), _msgSender(), currencyAmount);

        ISecuritizationPool(tge.pool()).onBuyNoteToken(currencyAmount);
        emit TokensPurchased(_msgSender(), tgeAddress, currencyAmount, tokenAmount);
    }

    function setAllowedUIDTypes(uint256[] calldata ids) external onlyRole(DEFAULT_ADMIN_ROLE) {
        allowedUIDTypes = ids;
    }

    function hasAllowedUID(address sender) public view override returns (bool) {
        return registry.getGo().goOnlyIdTypes(sender, allowedUIDTypes);
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
        uint256 poolsLength = pools.length;
        for (uint256 i = 0; i < poolsLength; i++) {
            pools[i].pause();
        }
    }

    function unpauseAllPools() external whenNotPaused nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 poolsLength = pools.length;
        for (uint256 i = 0; i < poolsLength; i++) {
            pools[i].unpause();
        }
    }
}
