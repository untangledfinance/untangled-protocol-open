// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '../../interfaces/IUntangledERC721.sol';
import '../../interfaces/INoteToken.sol';
import '../note-sale/MintedIncreasingInterestTGE.sol';
import '../../libraries/ConfigHelper.sol';
import '@openzeppelin/contracts/interfaces/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol';
import '@openzeppelin/contracts-upgradeable/interfaces/IERC721ReceiverUpgradeable.sol';

/**
 * @title Untangled's SecuritizationPool contract
 * @notice Main entry point for senior LPs (a.k.a. capital providers)
 *  Automatically invests across borrower pools using an adjustable strategy.
 * @author Untangled Team
 */
contract SecuritizationPool is ISecuritizationPool, IERC721ReceiverUpgradeable {
    using ConfigHelper for Registry;

    /** CONSTRUCTOR */
    function initialize(
        Registry _registry,
        address _currency,
        uint32 _minFirstLossCushion
    ) public override initializer {
        require(_minFirstLossCushion < 100 * RATE_SCALING_FACTOR, 'minFirstLossCushion is greater than 100');
        require(_currency != address(0), 'SecuritizationPool: Invalid currency');
        __UntangledBase__init(_msgSender());
        _setRoleAdmin(ORIGINATOR_ROLE, OWNER_ROLE);
        registry = _registry;

        state = CycleState.INITIATED;
        underlyingCurrency = _currency;
        minFirstLossCushion = _minFirstLossCushion;

        pot = address(this);
        require(IERC20(_currency).approve(pot, type(uint256).max), 'SecuritizationPool: Currency approval failed');
        registry.getLoanAssetToken().setApprovalForAll(address(registry.getLoanKernel()), true);
    }

    modifier onlyIssuingTokenStage() {
        require(state != CycleState.OPEN && state != CycleState.CLOSED, 'Not in issuing token stage');
        _;
    }

    modifier notClosingStage() {
        require(!isClosedState(), 'SecuritizationPool: Pool in closed state');
        _;
    }

    modifier finishRedemptionValidator() {
        require(hasFinishedRedemption(), 'SecuritizationPool: Redemption has not finished');
        _;
    }

    modifier onlySecuritizationManager() {
        require(
            _msgSender() == address(registry.getSecuritizationManager()),
            'SecuritizationPool: Only SecuritizationManager'
        );
        _;
    }

    modifier onlyDistributionOperator() {
        require(
            _msgSender() == address(registry.getDistributionOperator()),
            'SecuritizationPool: Only DistributionOperator'
        );
        _;
    }

    modifier onlyLoanRepaymentRouter() {
        require(
            _msgSender() == address(registry.getLoanRepaymentRouter()),
            'SecuritizationPool: Only LoanRepaymentRouter'
        );
        _;
    }

    /** GETTER */
    function getNFTAssetsLength() public view override returns (uint256) {
        return nftAssets.length;
    }

    function getTokenAssetAddresses() public view override returns (address[] memory) {
        return tokenAssetAddresses;
    }

    function getTokenAssetAddressesLength() public view override returns (uint256) {
        return tokenAssetAddresses.length;
    }

    function getRiskScoresLength() public view override returns (uint256) {
        return riskScores.length;
    }

    function isClosedState() public view override returns (bool) {
        return state == CycleState.CLOSED;
    }

    function hasFinishedRedemption() public view override returns (bool) {
        if (sotToken != address(0)) {
            require(IERC20(sotToken).totalSupply() == 0, 'SecuritizationPool: SOT still remain');
        }
        if (jotToken != address(0)) {
            require(IERC20(jotToken).totalSupply() == 0, 'SecuritizationPool: JOT still remain');
        }

        return true;
    }

    /** UTILITY FUNCTION */
    function _removeNFTAsset(address tokenAddress, uint256 tokenId) private returns (bool) {
        uint256 nftAssetsLength = nftAssets.length;
        for (uint256 i = 0; i < nftAssetsLength; i = UntangledMath.uncheckedInc(i)) {
            if (nftAssets[i].tokenAddress == tokenAddress && nftAssets[i].tokenId == tokenId) {
                // Remove i element from nftAssets
                _removeNFTAssetIndex(i);
                return true;
            }
        }

        return false;
    }

    function _removeNFTAssetIndex(uint256 indexToRemove) private {
        nftAssets[indexToRemove] = nftAssets[nftAssets.length - 1];
        nftAssets.pop();
    }

    function _pushTokenAssetAddress(address tokenAddress) private {
        if (!existsTokenAssetAddress[tokenAddress]) tokenAssetAddresses.push(tokenAddress);
        existsTokenAssetAddress[tokenAddress] = true;
    }

    function onERC721Received(
        address,
        address,
        uint256 tokenId,
        bytes memory
    ) external returns (bytes4) {
        require(
            _msgSender() == address(registry.getAcceptedInvoiceToken()) ||
                _msgSender() == address(registry.getLoanAssetToken()),
            'SecuritizationPool: Must be token issued by Untangled'
        );
        nftAssets.push(NFTAsset({tokenAddress: _msgSender(), tokenId: tokenId}));
        return this.onERC721Received.selector;
    }

    /// @inheritdoc ISecuritizationPool
    function setPot(address _pot) external override whenNotPaused nonReentrant notClosingStage onlyRole(OWNER_ROLE) {
        require(!hasRole(OWNER_ROLE, _pot));
        require(pot != _pot, 'SecuritizationPool: Same address with current pot');
        pot = _pot;
        if (_pot == address(this)) {
            require(IERC20(underlyingCurrency).approve(pot, type(uint256).max), 'SecuritizationPool: Pot not approved');
        }
        registry.getSecuritizationManager().registerPot(pot);
    }

    /// @inheritdoc ISecuritizationPool
    function setupRiskScores(
        uint32[] calldata _daysPastDues,
        uint32[] calldata _ratesAndDefaults,
        uint32[] calldata _periodsAndWriteOffs
    ) external override whenNotPaused notClosingStage onlyRole(OWNER_ROLE) {
        uint256 _daysPastDuesLength = _daysPastDues.length;
        require(
            _daysPastDuesLength * 5 == _ratesAndDefaults.length &&
                _daysPastDuesLength * 4 == _periodsAndWriteOffs.length,
            'SecuritizationPool: Riskscore params length is not equal'
        );
        delete riskScores;

        for (uint256 i = 0; i < _daysPastDuesLength; i = UntangledMath.uncheckedInc(i)) {
            require(
                i == 0 || _daysPastDues[i] > _daysPastDues[i - 1],
                'SecuritizationPool: Risk scores must be sorted'
            );
            riskScores.push(
                RiskScore({
                    daysPastDue: _daysPastDues[i],
                    advanceRate: _ratesAndDefaults[i],
                    penaltyRate: _ratesAndDefaults[i + _daysPastDuesLength],
                    interestRate: _ratesAndDefaults[i + _daysPastDuesLength * 2],
                    probabilityOfDefault: _ratesAndDefaults[i + _daysPastDuesLength * 3],
                    lossGivenDefault: _ratesAndDefaults[i + _daysPastDuesLength * 4],
                    gracePeriod: _periodsAndWriteOffs[i],
                    collectionPeriod: _periodsAndWriteOffs[i + _daysPastDuesLength],
                    writeOffAfterGracePeriod: _periodsAndWriteOffs[i + _daysPastDuesLength * 2],
                    writeOffAfterCollectionPeriod: _periodsAndWriteOffs[i + _daysPastDuesLength * 3]
                })
            );
        }
    }

    /// @inheritdoc ISecuritizationPool
    function exportAssets(
        address tokenAddress,
        address toPoolAddress,
        uint256[] calldata tokenIds
    ) external override whenNotPaused nonReentrant notClosingStage onlyRole(OWNER_ROLE) {
        uint256 tokenIdsLength = tokenIds.length;
        for (uint256 i = 0; i < tokenIdsLength; i = UntangledMath.uncheckedInc(i)) {
            require(_removeNFTAsset(tokenAddress, tokenIds[i]), 'SecuritizationPool: Asset does not exist');
        }

        for (uint256 i = 0; i < tokenIdsLength; i = UntangledMath.uncheckedInc(i)) {
            IUntangledERC721(tokenAddress).safeTransferFrom(address(this), toPoolAddress, tokenIds[i]);
        }
}

    /// @inheritdoc ISecuritizationPool
    function withdrawAssets(
        address[] calldata tokenAddresses,
        uint256[] calldata tokenIds,
        address[] calldata recipients
    ) external override whenNotPaused nonReentrant onlyRole(OWNER_ROLE) {
        uint256 tokenIdsLength = tokenIds.length;
        require(tokenAddresses.length == tokenIdsLength, 'tokenAddresses length and tokenIds length are not equal');
        require(
            tokenAddresses.length == recipients.length,
            'tokenAddresses length and recipients length are not equal'
        );

        for (uint256 i = 0; i < tokenIdsLength; i = UntangledMath.uncheckedInc(i)) {
            require(_removeNFTAsset(tokenAddresses[i], tokenIds[i]), 'SecuritizationPool: Asset does not exist');
        }
        for (uint256 i = 0; i < tokenIdsLength; i = UntangledMath.uncheckedInc(i)) {
            IUntangledERC721(tokenAddresses[i]).safeTransferFrom(address(this), recipients[i], tokenIds[i]);
        }
    }

    /// @inheritdoc ISecuritizationPool
    function collectAssets(
        address tokenAddress,
        address from,
        uint256[] calldata tokenIds
    ) external override whenNotPaused onlyRole(ORIGINATOR_ROLE) {
        uint256 tokenIdsLength = tokenIds.length;
        for (uint256 i = 0; i < tokenIdsLength; i = UntangledMath.uncheckedInc(i)) {
            IUntangledERC721(tokenAddress).safeTransferFrom(from, address(this), tokenIds[i]);
        }
        uint256 expectedAssetsValue = 0;
        ISecuritizationPoolValueService poolService = registry.getSecuritizationPoolValueService();
        for (uint256 i = 0; i < tokenIdsLength; i = UntangledMath.uncheckedInc(i)) {
            expectedAssetsValue =
                expectedAssetsValue +
                poolService.getExpectedAssetValue(address(this), tokenAddress, tokenIds[i], block.timestamp);
        }
        amountOwedToOriginator += expectedAssetsValue;
        if (firstAssetTimestamp == 0) {
            firstAssetTimestamp = uint64(block.timestamp);
            _setUpOpeningBlockTimestamp();
        }
        if (openingBlockTimestamp == 0) { // If openingBlockTimestamp is not set
           openingBlockTimestamp = uint64(block.timestamp);
        }
    }

    /// @inheritdoc ISecuritizationPool
    function withdraw(uint256 amount) public override whenNotPaused nonReentrant onlyRole(ORIGINATOR_ROLE) {
        uint256 _amountOwedToOriginator = amountOwedToOriginator;
        if (amount <= _amountOwedToOriginator) {
            amountOwedToOriginator = _amountOwedToOriginator - amount;
        } else {
            amountOwedToOriginator = 0;
        }
        reserve = reserve - amount;
        require(checkMinFirstLost(), 'MinFirstLoss is not satisfied');
        require(
            IERC20(underlyingCurrency).transferFrom(pot, _msgSender(), amount),
            'SecuritizationPool: Transfer failed'
        );
        emit Withdraw(_msgSender(), amount);
    }

    function checkMinFirstLost() public view returns (bool) {
        ISecuritizationPoolValueService poolService = registry.getSecuritizationPoolValueService();
        return minFirstLossCushion <= poolService.getJuniorRatio(address(this));
    }

    /// @inheritdoc ISecuritizationPool
    function collectERC20Assets(
        address[] calldata tokenAddresses,
        address[] calldata senders,
        uint256[] calldata amounts
    ) external override whenNotPaused notClosingStage onlyRole(ORIGINATOR_ROLE) {
        uint256 tokenAddressesLength = tokenAddresses.length;
        require(
            tokenAddressesLength == senders.length && senders.length == amounts.length,
            'SecuritizationPool: Params length are not equal'
        );

        // check
        for (uint256 i = 0; i < tokenAddressesLength; i = UntangledMath.uncheckedInc(i)) {
            require(
                registry.getNoteTokenFactory().isExistingTokens(tokenAddresses[i]),
                'SecuritizationPool: unknown-token-address'
            );
        }

        for (uint256 i = 0; i < tokenAddressesLength; i = UntangledMath.uncheckedInc(i)) {
            _pushTokenAssetAddress(tokenAddresses[i]);
        }

        for (uint256 i = 0; i < tokenAddressesLength; i = UntangledMath.uncheckedInc(i)) {
            require(
                IERC20(tokenAddresses[i]).transferFrom(senders[i], address(this), amounts[i]),
                'SecuritizationPool: Transfer failed'
            );
        }

        if (openingBlockTimestamp == 0) {  // If openingBlockTimestamp is not set
            openingBlockTimestamp = uint64(block.timestamp);
        }
    }

    /// @inheritdoc ISecuritizationPool
    function withdrawERC20Assets(
        address[] calldata tokenAddresses,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external override whenNotPaused nonReentrant onlyRole(OWNER_ROLE) {
        uint256 tokenAddressesLength = tokenAddresses.length;
        require(tokenAddressesLength == recipients.length, 'tokenAddresses length and tokenIds length are not equal');
        require(tokenAddressesLength == amounts.length, 'tokenAddresses length and recipients length are not equal');
        for (uint256 i = 0; i < tokenAddressesLength; i = UntangledMath.uncheckedInc(i)) {
            require(existsTokenAssetAddress[tokenAddresses[i]], 'SecuritizationPool: note token asset does not exist');
            require(
                IERC20(tokenAddresses[i]).transfer(recipients[i], amounts[i]),
                'SecuritizationPool: Transfer failed'
            );
        }
    }

    // After closed pool and redeem all not -> get remain cash to recipient wallet
    /// @inheritdoc ISecuritizationPool
    function claimCashRemain(address recipientWallet)
        external
        override
        whenNotPaused
        nonReentrant
        onlyRole(OWNER_ROLE)
        finishRedemptionValidator
    {
        IERC20 currency = IERC20(underlyingCurrency);
        require(
            currency.transferFrom(pot, recipientWallet, currency.balanceOf(pot)),
            'SecuritizationPool: Transfer failed'
        );
    }

    /// @inheritdoc ISecuritizationPool
    function injectTGEAddress(
        address _tgeAddress,
        address _tokenAddress,
        Configuration.NOTE_TOKEN_TYPE _noteType
    ) external override whenNotPaused onlySecuritizationManager onlyIssuingTokenStage {
        require(_tgeAddress != address(0x0) && _tokenAddress != address(0x0), 'SecuritizationPool: Address zero');

        if (_noteType == Configuration.NOTE_TOKEN_TYPE.SENIOR) {
            tgeAddress = _tgeAddress;
            sotToken = _tokenAddress;
        } else {
            secondTGEAddress = _tgeAddress;
            jotToken = _tokenAddress;
        }
        state = CycleState.CROWDSALE;
    }

    /// @inheritdoc ISecuritizationPool
    function startCycle(
        uint64 _termLengthInSeconds,
        uint256 _principalAmountForSOT,
        uint32 _interestRateForSOT,
        uint64 _timeStartEarningInterest
    ) external override whenNotPaused nonReentrant onlyRole(OWNER_ROLE) onlyIssuingTokenStage {
        require(_termLengthInSeconds > 0, 'SecuritizationPool: Term length is 0');

        termLengthInSeconds = _termLengthInSeconds;

        principalAmountSOT = _principalAmountForSOT;

        state = CycleState.OPEN;

        if (tgeAddress != address(0)) {
            MintedIncreasingInterestTGE mintedTokenGenrationEvent = MintedIncreasingInterestTGE(tgeAddress);
            mintedTokenGenrationEvent.setupLongSale(
                _interestRateForSOT,
                _termLengthInSeconds,
                _timeStartEarningInterest
            );
            if (!mintedTokenGenrationEvent.finalized()) {
                mintedTokenGenrationEvent.finalize(false, pot);
            }
            interestRateSOT = mintedTokenGenrationEvent.pickedInterest();
        }
        if (secondTGEAddress != address(0)) {
            FinalizableCrowdsale(secondTGEAddress).finalize(false, pot);
            require(
                MintedIncreasingInterestTGE(secondTGEAddress).finalized(),
                'SecuritizationPool: second sale is still on going'
            );
        }
    }

    /// @inheritdoc ISecuritizationPool
    function setInterestRateForSOT(uint32 _interestRateSOT) external override whenNotPaused {
        require(_msgSender() == tgeAddress, 'SecuritizationPool: Only tge can update interest');
        interestRateSOT = _interestRateSOT;
    }

    // Increase by value
    /// @inheritdoc ISecuritizationPool
    function increaseLockedDistributeBalance(
        address tokenAddress,
        address investor,
        uint256 currency,
        uint256 token
    ) external override whenNotPaused onlyDistributionOperator {
        lockedDistributeBalances[tokenAddress][investor] = lockedDistributeBalances[tokenAddress][investor] + currency;
        lockedRedeemBalances[tokenAddress][investor] = lockedRedeemBalances[tokenAddress][investor] + token;

        totalLockedDistributeBalance = totalLockedDistributeBalance + currency;
        totalLockedRedeemBalances[tokenAddress] = totalLockedRedeemBalances[tokenAddress] + token;
    }

    // Decrease by value

    /// @inheritdoc ISecuritizationPool
    function decreaseLockedDistributeBalance(
        address tokenAddress,
        address investor,
        uint256 currency,
        uint256 token
    ) external override whenNotPaused onlyDistributionOperator {
        lockedDistributeBalances[tokenAddress][investor] = lockedDistributeBalances[tokenAddress][investor] - currency;
        lockedRedeemBalances[tokenAddress][investor] = lockedRedeemBalances[tokenAddress][investor] - token;

        totalLockedDistributeBalance = totalLockedDistributeBalance - currency;
        totalRedeemedCurrency = totalRedeemedCurrency + currency;
        totalLockedRedeemBalances[tokenAddress] = totalLockedRedeemBalances[tokenAddress] - token;
    }

    // Increase by value
    /// @inheritdoc ISecuritizationPool
    function increaseTotalAssetRepaidCurrency(uint256 amount) external override whenNotPaused onlyLoanRepaymentRouter {
        reserve = reserve + amount;
        totalAssetRepaidCurrency = totalAssetRepaidCurrency + amount;
    }

    /// @inheritdoc ISecuritizationPool
    function redeem(
        address usr,
        address notesToken,
        uint256 currencyAmount,
        uint256 tokenAmount
    ) external override whenNotPaused nonReentrant {
        require(
            _msgSender() == address(registry.getDistributionTranche()),
            'SecuritizationPool: Caller must be DistributionTranche'
        );
        if (sotToken == notesToken) {
            paidPrincipalAmountSOTByInvestor[usr] += currencyAmount;
        }
        reserve = reserve - currencyAmount;

        if (tokenAmount > 0) {
            ERC20Burnable(notesToken).burn(tokenAmount);
        }

        require(checkMinFirstLost(), 'MinFirstLoss is not satisfied');
        require(
            IERC20(underlyingCurrency).transferFrom(pot, usr, currencyAmount),
            'SecuritizationPool: currency-transfer-failed'
        );
    }

    /// @inheritdoc ISecuritizationPool
    function increaseReserve(uint256 currencyAmount) external override whenNotPaused {
        require(
            _msgSender() == address(registry.getSecuritizationManager()) || _msgSender() == address(registry.getDistributionOperator()),
            'SecuritizationPool: Caller must be SecuritizationManager or DistributionOperator');
        reserve = reserve + currencyAmount;
        require(checkMinFirstLost(), 'MinFirstLoss is not satisfied');
    }

    /// @inheritdoc ISecuritizationPool
    function decreaseReserve(
        uint256 currencyAmount
    ) external override whenNotPaused {
        require(
            _msgSender() == address(registry.getSecuritizationManager()) || _msgSender() == address(registry.getDistributionOperator()),
            'SecuritizationPool: Caller must be SecuritizationManager or DistributionOperator');
        reserve = reserve - currencyAmount;
        require(checkMinFirstLost(), 'MinFirstLoss is not satisfied');
    }

    /// @inheritdoc ISecuritizationPool
    function setUpOpeningBlockTimestamp() public override whenNotPaused {
        require( _msgSender() == tgeAddress, "SecuritizationPool: Only tge address");
        _setUpOpeningBlockTimestamp();
    }

    /// @dev Set the opening block timestamp
    function _setUpOpeningBlockTimestamp() private {
        if (tgeAddress == address(0)) return;
        uint64 _firstNoteTokenMintedTimestamp = ICrowdSale(tgeAddress).firstNoteTokenMintedTimestamp();
        uint64 _firstAssetTimestamp = firstAssetTimestamp;
        if (_firstNoteTokenMintedTimestamp > 0 && _firstAssetTimestamp > 0) {
            // Pick the later
            if (_firstAssetTimestamp > _firstNoteTokenMintedTimestamp) {
                openingBlockTimestamp = _firstAssetTimestamp;
            } else {
                openingBlockTimestamp = _firstNoteTokenMintedTimestamp;
            }
        }
    }

    uint256[50] private __gap;
}
