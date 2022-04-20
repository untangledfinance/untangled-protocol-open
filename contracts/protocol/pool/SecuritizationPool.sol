// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../../interfaces/IUntangledERC721.sol';
import '../../interfaces/INoteToken.sol';
import '../../interfaces/IMintedTokenGenerationEvent.sol';
import '../../libraries/ConfigHelper.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol';

contract SecuritizationPool is ISecuritizationPool, IERC721ReceiverUpgradeable {
    using ConfigHelper for Registry;

    /** CONSTRUCTOR */
    function initialize(
        address owner,
        Registry _registry,
        address _currency,
        uint32 _minFirstLossCushion
    ) public override initializer {
        __UntangledBase__init(owner);

        registry = _registry;

        pot = address(this);
        IERC20(_currency).approve(pot, type(uint256).max);

        state = CycleState.INITIATED;
        underlyingCurrency = _currency;
        minFirstLossCushion = _minFirstLossCushion;
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
            'ecuritizationPool: Only DistributionOperator'
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
    function removeNFTAsset(address tokenAddress, uint256 tokenId) private returns (bool) {
        for (uint256 i = 0; i < nftAssets.length; i++) {
            if (nftAssets[i].tokenAddress == tokenAddress && nftAssets[i].tokenId == tokenId) {
                // Remove i element from nftAssets
                removeNFTAssetIndex(i);
                return true;
            }
        }

        return false;
    }

    function removeNFTAssetIndex(uint256 indexToRemove) private {
        nftAssets[indexToRemove] = nftAssets[nftAssets.length - 1];
        nftAssets.pop();
    }

    function pushTokenAssetAddress(address tokenAddress) private {
        if (!existsTokenAssetAddress[tokenAddress]) tokenAssetAddresses.push(tokenAddress);
        existsTokenAssetAddress[tokenAddress] = true;
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes memory data
    ) external returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /** EXTERNAL */
    function setPot(address _pot) external override whenNotPaused nonReentrant notClosingStage onlyRole(OWNER_ROLE) {
        require(pot != _pot, 'SecuritizationPool: Same address with current pot');
        pot = _pot;
        if (pot == address(this)) {
            IERC20(underlyingCurrency).approve(pot, type(uint256).max);
        }
    }

    function setupRiskScores(
        uint32[] calldata _daysPastDues,
        uint32[] calldata _ratesAndDefaults,
        uint32[] calldata _periodsAndWriteOffs
    ) external override whenNotPaused nonReentrant notClosingStage onlyRole(OWNER_ROLE) {
        require(
            _daysPastDues.length * 5 == _ratesAndDefaults.length &&
                _daysPastDues.length * 4 == _periodsAndWriteOffs.length,
            'SecuritizationPool: Riskscore params length is not equal'
        );
        delete riskScores;
        for (uint256 i = 0; i < _daysPastDues.length; i++) {
            require(
                i == 0 || _daysPastDues[i] > _daysPastDues[i - 1],
                'SecuritizationPool: Risk scores must be sorted'
            );
            riskScores.push(
                RiskScore({
                    daysPastDue: _daysPastDues[i],
                    advanceRate: _ratesAndDefaults[i],
                    penaltyRate: _ratesAndDefaults[i + _daysPastDues.length],
                    interestRate: _ratesAndDefaults[i + _daysPastDues.length * 2],
                    probabilityOfDefault: _ratesAndDefaults[i + _daysPastDues.length * 3],
                    lossGivenDefault: _ratesAndDefaults[i + _daysPastDues.length * 4],
                    gracePeriod: _periodsAndWriteOffs[i],
                    collectionPeriod: _periodsAndWriteOffs[i + _daysPastDues.length],
                    writeOffAfterGracePeriod: _periodsAndWriteOffs[i + _daysPastDues.length * 2],
                    writeOffAfterCollectionPeriod: _periodsAndWriteOffs[i + _daysPastDues.length * 3]
                })
            );
        }
    }

    function collectAssets(
        address tokenAddress,
        address from,
        uint256[] calldata tokenIds
    ) external override whenNotPaused nonReentrant notClosingStage onlyRole(ORIGINATOR_ROLE) {
        require(
            tokenAddress == address(registry.getAcceptedInvoiceToken()) ||
                tokenAddress == address(registry.getLoanAssetToken()),
            'SecuritizationPool: Must be token issued by Untangled'
        );
        for (uint256 i = 0; i < tokenIds.length; ++i) {
            nftAssets.push(NFTAsset({tokenAddress: tokenAddress, tokenId: tokenIds[i]}));
        }
        IUntangledERC721(tokenAddress).safeBatchTransferFrom(from, address(this), tokenIds);
    }

    function exportAssets(
        address tokenAddress,
        address toPoolAddress,
        uint256[] calldata tokenIds
    ) external override whenNotPaused nonReentrant notClosingStage onlyRole(OWNER_ROLE) {
        for (uint256 i = 0; i < tokenIds.length; ++i) {
            require(removeNFTAsset(tokenAddress, tokenIds[i]), 'SecuritizationPool: Asset does not exist');
            IUntangledERC721(tokenAddress).approve(toPoolAddress, tokenIds[i]);
        }
        ISecuritizationPool(toPoolAddress).collectAssets(tokenAddress, address(this), tokenIds);
    }

    function withdrawAssets(
        address[] calldata tokenAddresses,
        uint256[] calldata tokenIds,
        address[] calldata recipients
    ) external override whenNotPaused nonReentrant onlyRole(OWNER_ROLE) {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(removeNFTAsset(tokenAddresses[i], tokenIds[i]), 'SecuritizationPool: Asset does not exist');
            IUntangledERC721(tokenAddresses[i]).safeTransferFrom(address(this), recipients[i], tokenIds[i]);
        }
    }

    function updateExistedAsset() external override whenNotPaused nonReentrant {
        uint256 i = 0;
        while (i < getNFTAssetsLength()) {
            if (IUntangledERC721(nftAssets[i].tokenAddress).ownerOf(nftAssets[i].tokenId) != address(this)) {
                removeNFTAssetIndex(i);
            } else i++;
        }
    }

    function collectERC20Assets(
        address[] calldata tokenAddresses,
        address[] calldata senders,
        uint256[] calldata amounts
    ) external override whenNotPaused nonReentrant notClosingStage onlyRole(ORIGINATOR_ROLE) {
        require(
            tokenAddresses.length == senders.length && senders.length == amounts.length,
            'SecuritizationPool: Params length are not equal'
        );
        ISecuritizationManager securitizationManager = registry.getSecuritizationManager();
        for (uint256 i = 0; i < tokenAddresses.length; ++i) {
            require(
                securitizationManager.isExistingNoteToken(
                    INoteToken(tokenAddresses[i]).poolAddress(),
                    tokenAddresses[i]
                ),
                'SecuritizationPool: unknown-token-address'
            );
            IERC20(tokenAddresses[i]).transferFrom(senders[i], address(this), amounts[i]);
            pushTokenAssetAddress(tokenAddresses[i]);
        }
    }

    function withdrawERC20Assets(
        address[] calldata tokenAddresses,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external override whenNotPaused nonReentrant onlyRole(OWNER_ROLE) {
        for (uint256 i = 0; i < tokenAddresses.length; ++i) {
            require(existsTokenAssetAddress[tokenAddresses[i]], 'SecuritizationPool: note token asset does not exist');
            IERC20(tokenAddresses[i]).transfer(recipients[i], amounts[i]);
        }
    }

    function claimERC20Assets(address[] calldata tokenAddresses) external override whenNotPaused nonReentrant {
        ISecuritizationManager securitizationManager = registry.getSecuritizationManager();
        for (uint256 i = 0; i < tokenAddresses.length; ++i) {
            require(
                securitizationManager.isExistingNoteToken(
                    INoteToken(tokenAddresses[i]).poolAddress(),
                    tokenAddresses[i]
                ),
                'SecuritizationPool: unknown-token-address'
            );
            require(
                IERC20(tokenAddresses[i]).balanceOf(address(this)) > 0,
                'SecuritizationPool: Token balance is zero'
            );
            pushTokenAssetAddress(tokenAddresses[i]);
        }
    }

    // After closed pool and redeem all not -> get remain cash to recipient wallet
    function claimCashRemain(address recipientWallet)
        external
        override
        whenNotPaused
        nonReentrant
        onlyRole(OWNER_ROLE)
        finishRedemptionValidator
    {
        IERC20 currency = IERC20(underlyingCurrency);
        currency.transferFrom(pot, recipientWallet, currency.balanceOf(pot));
    }

    function injectTGEAddress(
        address _tgeAddress,
        address _tokenAddress,
        Configuration.NOTE_TOKEN_TYPE _noteType
    ) external override whenNotPaused nonReentrant onlySecuritizationManager onlyIssuingTokenStage {
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

    function startCycle(
        uint64 _termLengthInSeconds,
        uint256 _principalAmountForSOT,
        uint32 _interestRateForSOT,
        uint64 _timeStartEarningInterest
    ) external override whenNotPaused nonReentrant onlyRole(OWNER_ROLE) onlyIssuingTokenStage {
        if (tgeAddress != address(0)) {
            IMintedTokenGenerationEvent mintedTokenGenrationEvent = IMintedTokenGenerationEvent(tgeAddress);
            require(mintedTokenGenrationEvent.finalized(), 'SecuritizationPool: sale is still on going');
            IMintedTokenGenerationEvent(tgeAddress).setupLongSale(
                _interestRateForSOT,
                _termLengthInSeconds,
                _timeStartEarningInterest
            );
        }
        if (secondTGEAddress != address(0)) {
            require(
                IMintedTokenGenerationEvent(secondTGEAddress).finalized(),
                'SecuritizationPool: second sale is still on going'
            );
        }
        require(_termLengthInSeconds > 0, 'SecuritizationPool: Term length is 0');

        openingBlockTimestamp = _timeStartEarningInterest;
        termLengthInSeconds = _termLengthInSeconds;

        principalAmountSOT = _principalAmountForSOT;
        if (interestRateSOT == 0) {
            interestRateSOT = _interestRateForSOT;
        }

        state = CycleState.OPEN;
    }

    function setInterestRateForSOT(uint32 _interestRateSOT) external override whenNotPaused {
        require(_msgSender() == tgeAddress, 'SecuritizationPool: Only tge can update interest');
        interestRateSOT = _interestRateSOT;
    }

    // Increase by value
    function increaseLockedDistributeBalance(
        address tokenAddress,
        address investor,
        uint256 currency,
        uint256 token
    ) external override whenNotPaused nonReentrant onlyDistributionOperator {
        lockedDistributeBalances[tokenAddress][investor] = lockedDistributeBalances[tokenAddress][investor] + currency;
        lockedRedeemBalances[tokenAddress][investor] = lockedRedeemBalances[tokenAddress][investor] + token;

        totalLockedDistributeBalance = totalLockedDistributeBalance + currency;
        totalLockedRedeemBalances[tokenAddress] = totalLockedRedeemBalances[tokenAddress] + token;
    }

    // Decrease by value
    function decreaseLockedDistributeBalance(
        address tokenAddress,
        address investor,
        uint256 currency,
        uint256 token
    ) external override whenNotPaused nonReentrant onlyDistributionOperator {
        lockedDistributeBalances[tokenAddress][investor] = lockedDistributeBalances[tokenAddress][investor] - currency;
        lockedRedeemBalances[tokenAddress][investor] = lockedRedeemBalances[tokenAddress][investor] - token;

        totalLockedDistributeBalance = totalLockedDistributeBalance - currency;
        totalLockedRedeemBalances[tokenAddress] = totalLockedRedeemBalances[tokenAddress] - token;
    }

    function increasePaidInterestAmountSOT(address investor, uint256 amount)
        external
        override
        whenNotPaused
        nonReentrant
        onlyDistributionOperator
    {
        paidInterestAmountSOT[investor] = paidInterestAmountSOT[investor] + amount;
        lastRepayTimestampSOT[investor] = block.timestamp;
    }

    function increasePaidPrincipalAmountSOT(address _investor, uint256 _paidPrincipalAmountSOT)
        public
        override
        whenNotPaused
        nonReentrant
        onlyDistributionOperator
    {
        paidPrincipalAmountSOTByInvestor[_investor] =
            paidPrincipalAmountSOTByInvestor[_investor] +
            _paidPrincipalAmountSOT;
        paidPrincipalAmountSOT = paidPrincipalAmountSOT + _paidPrincipalAmountSOT;
        require(
            IMintedTokenGenerationEvent(tgeAddress).currencyRaised() >= paidPrincipalAmountSOT,
            'SecuritizationPool: exceed amount paid for SOT'
        );
    }

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

        if (tokenAmount > 0) {
            ERC20Burnable(notesToken).burn(tokenAmount);
        }
        require(
            IERC20(underlyingCurrency).transferFrom(pot, usr, currencyAmount),
            'SecuritizationPool: currency-transfer-failed'
        );
    }
}
