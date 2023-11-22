// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ERC165Upgradeable} from '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol';
import {ReentrancyGuardUpgradeable} from '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import {PausableUpgradeable} from '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import {ERC20BurnableUpgradeable} from '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol';
import {IERC20Upgradeable} from '@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol';
import {Registry} from '../../storage/Registry.sol';
import {ConfigHelper} from '../../libraries/ConfigHelper.sol';
import {ISecuritizationTGE} from './ISecuritizationTGE.sol';
import {Configuration} from '../../libraries/Configuration.sol';
import {ISecuritizationPoolValueService} from './ISecuritizationPoolValueService.sol';
import {RegistryInjection} from './RegistryInjection.sol';
import {SecuritizationAccessControl} from './SecuritizationAccessControl.sol';
import {IMintedTGE} from '../note-sale/IMintedTGE.sol';
import {IFinalizableCrowdsale} from '../note-sale/crowdsale/IFinalizableCrowdsale.sol';
import {SecuritizationPoolStorage} from './SecuritizationPoolStorage.sol';
import {ISecuritizationPoolExtension} from './ISecuritizationPoolExtension.sol';
import {ISecuritizationPoolStorage} from './ISecuritizationPoolStorage.sol';

import {ORIGINATOR_ROLE} from './types.sol';

import 'hardhat/console.sol';

contract SecuritizationTGE is
    RegistryInjection,
    ERC165Upgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    SecuritizationAccessControl,
    SecuritizationPoolStorage,
    ISecuritizationTGE
{
    using ConfigHelper for Registry;

    function installExtension(
        bytes memory params
    ) public virtual override(SecuritizationAccessControl, SecuritizationPoolStorage) {
        __SecuritizationTGE_init_unchained(abi.decode(params, (NewPoolParams)));
    }

    function __SecuritizationTGE_init_unchained(NewPoolParams memory params) internal {
        Storage storage $ = _getStorage();
        $.pot = address(this);
        $.state = CycleState.INITIATED;

        $.underlyingCurrency = params.currency;
        $.minFirstLossCushion = params.minFirstLossCushion;
    }

    function sotToken() public view override returns (address) {
        return _getStorage().sotToken;
    }

    function jotToken() public view override returns (address) {
        return _getStorage().jotToken;
    }

    function underlyingCurrency() public view override returns (address) {
        return _getStorage().underlyingCurrency;
    }

    function reserve() public view override returns (uint256) {
        return _getStorage().reserve;
    }

    function minFirstLossCushion() public view override returns (uint32) {
        return _getStorage().minFirstLossCushion;
    }

    function termLengthInSeconds() public view override returns (uint64) {
        return _getStorage().termLengthInSeconds;
    }

    function paidPrincipalAmountSOT() public view override returns (uint256) {
        return _getStorage().paidPrincipalAmountSOT;
    }

    function principalAmountSOT() public view override returns (uint256) {
        return _getStorage().principalAmountSOT;
    }

    function interestRateSOT() public view override returns (uint32) {
        return _getStorage().interestRateSOT;
    }

    function paidPrincipalAmountSOTByInvestor(address user) public view override returns (uint256) {
        return _getStorage().paidPrincipalAmountSOTByInvestor[user];
    }

    function totalAssetRepaidCurrency() public view override returns (uint256) {
        return _getStorage().totalAssetRepaidCurrency;
    }

    modifier finishRedemptionValidator() {
        require(hasFinishedRedemption(), 'SecuritizationPool: Redemption has not finished');
        _;
    }

    // modifier notClosingStage() {
    //     require(!isClosedState(), 'SecuritizationPool: Pool in closed state');
    //     _;
    // }

    // function isClosedState() public view override returns (bool) {
    //     return state() == CycleState.CLOSED;
    // }

    /// @inheritdoc ISecuritizationTGE
    function injectTGEAddress(
        address _tgeAddress,
        address _tokenAddress,
        Configuration.NOTE_TOKEN_TYPE _noteType
    ) external override whenNotPaused onlyIssuingTokenStage {
        registry().requireSecuritizationManager(_msgSender());
        require(_tgeAddress != address(0x0) && _tokenAddress != address(0x0), 'SecuritizationPool: Address zero');

        Storage storage $ = _getStorage();

        if (_noteType == Configuration.NOTE_TOKEN_TYPE.SENIOR) {
            $.tgeAddress = _tgeAddress;
            $.sotToken = _tokenAddress;
        } else {
            $.secondTGEAddress = _tgeAddress;
            $.jotToken = _tokenAddress;
        }

        $.state = CycleState.CROWDSALE;

        emit UpdateTGEAddress(_tgeAddress, _tokenAddress, _noteType);
    }

    /// @notice allows the redemption of tokens
    function redeem(
        address usr,
        address notesToken,
        uint256 currencyAmount,
        uint256 tokenAmount
    ) external virtual override {
        require(
            _msgSender() == address(registry().getDistributionTranche()),
            'SecuritizationPool: Caller must be DistributionTranche'
        );

        Storage storage $ = _getStorage();

        if ($.sotToken == notesToken) {
            $.paidPrincipalAmountSOTByInvestor[usr] += currencyAmount;
            emit UpdatePaidPrincipalAmountSOTByInvestor(usr, currencyAmount);
        }

        $.reserve = $.reserve - currencyAmount;

        if (tokenAmount > 0) {
            ERC20BurnableUpgradeable(notesToken).burn(tokenAmount);
        }

        require(checkMinFirstLost(), 'MinFirstLoss is not satisfied');
        require(
            IERC20Upgradeable($.underlyingCurrency).transferFrom($.pot, usr, currencyAmount),
            'SecuritizationPool: currency-transfer-failed'
        );

        emit UpdateReserve($.reserve);
    }

    function checkMinFirstLost() public view virtual returns (bool) {
        ISecuritizationPoolValueService poolService = registry().getSecuritizationPoolValueService();
        return _getStorage().minFirstLossCushion <= poolService.getJuniorRatio(address(this));
    }

    // Increase by value
    function increaseTotalAssetRepaidCurrency(uint256 amount) external virtual override whenNotPaused {
        registry().requireLoanRepaymentRouter(_msgSender());

        Storage storage $ = _getStorage();

        $.reserve = $.reserve + amount;
        $.totalAssetRepaidCurrency = $.totalAssetRepaidCurrency + amount;

        emit UpdateReserve($.reserve);
    }

    function hasFinishedRedemption() public view override returns (bool) {
        Storage storage $ = _getStorage();

        if ($.sotToken != address(0)) {
            require(IERC20Upgradeable($.sotToken).totalSupply() == 0, 'SecuritizationPool: SOT still remain');
        }
        if ($.jotToken != address(0)) {
            require(IERC20Upgradeable($.jotToken).totalSupply() == 0, 'SecuritizationPool: JOT still remain');
        }

        return true;
    }

    function setPot(address _pot) external override whenNotPaused nonReentrant notClosingStage {
        registry().requirePoolAdminOrOwner(address(this), _msgSender());

        Storage storage $ = _getStorage();

        require($.pot != _pot, 'SecuritizationPool: Same address with current pot');
        $.pot = _pot;
        if (_pot == address(this)) {
            require(
                IERC20Upgradeable($.underlyingCurrency).approve($.pot, type(uint256).max),
                'SecuritizationPool: Pot not approved'
            );
        }
        registry().getSecuritizationManager().registerPot($.pot);
    }

    function increaseReserve(uint256 currencyAmount) external override whenNotPaused {
        require(
            _msgSender() == address(registry().getSecuritizationManager()) ||
                _msgSender() == address(registry().getDistributionOperator()),
            'SecuritizationPool: Caller must be SecuritizationManager or DistributionOperator'
        );

        Storage storage $ = _getStorage();

        $.reserve = $.reserve + currencyAmount;
        require(checkMinFirstLost(), 'MinFirstLoss is not satisfied');

        emit UpdateReserve($.reserve);
    }

    function decreaseReserve(uint256 currencyAmount) external override whenNotPaused {
        require(
            _msgSender() == address(registry().getSecuritizationManager()) ||
                _msgSender() == address(registry().getDistributionOperator()),
            'SecuritizationPool: Caller must be SecuritizationManager or DistributionOperator'
        );

        Storage storage $ = _getStorage();
        $.reserve = $.reserve - currencyAmount;
        require(checkMinFirstLost(), 'MinFirstLoss is not satisfied');

        emit UpdateReserve($.reserve);
    }

    function setInterestRateForSOT(uint32 _interestRateSOT) external override whenNotPaused {
        Storage storage $ = _getStorage();
        require(_msgSender() == $.tgeAddress, 'SecuritizationPool: Only tge can update interest');

        $.interestRateSOT = _interestRateSOT;
        emit UpdateInterestRateSOT(_interestRateSOT);
    }

    // After closed pool and redeem all not -> get remain cash to recipient wallet
    function claimCashRemain(
        address recipientWallet
    ) external override whenNotPaused onlyOwner finishRedemptionValidator {
        Storage storage $ = _getStorage();

        IERC20Upgradeable currency = IERC20Upgradeable($.underlyingCurrency);
        require(
            currency.transferFrom($.pot, recipientWallet, currency.balanceOf($.pot)),
            'SecuritizationPool: Transfer failed'
        );
    }

    function startCycle(
        uint64 _termLengthInSeconds,
        uint256 _principalAmountForSOT,
        uint32 _interestRateForSOT,
        uint64 _timeStartEarningInterest
    ) external override whenNotPaused nonReentrant onlyOwner onlyIssuingTokenStage {
        require(_termLengthInSeconds > 0, 'SecuritizationPool: Term length is 0');

        Storage storage $ = _getStorage();

        $.termLengthInSeconds = _termLengthInSeconds;

        $.principalAmountSOT = _principalAmountForSOT;

        $.state = CycleState.OPEN;

        if ($.tgeAddress != address(0)) {
            IMintedTGE mintedTokenGenerationEvent = IMintedTGE($.tgeAddress);
            mintedTokenGenerationEvent.setupLongSale(
                _interestRateForSOT,
                _termLengthInSeconds,
                _timeStartEarningInterest
            );
            if (!IFinalizableCrowdsale($.tgeAddress).finalized()) {
                IFinalizableCrowdsale($.tgeAddress).finalize(false, $.pot);
            }
            $.interestRateSOT = mintedTokenGenerationEvent.pickedInterest();
        }
        if ($.secondTGEAddress != address(0)) {
            IFinalizableCrowdsale($.secondTGEAddress).finalize(false, $.pot);
            require(
                IFinalizableCrowdsale($.secondTGEAddress).finalized(),
                'SecuritizationPool: second sale is still on going'
            );
        }
    }

    function withdraw(uint256 amount) public override whenNotPaused onlyRole(ORIGINATOR_ROLE) {
        Storage storage $ = _getStorage();
        uint256 _amountOwedToOriginator = $.amountOwedToOriginator;
        if (amount <= _amountOwedToOriginator) {
            $.amountOwedToOriginator = _amountOwedToOriginator - amount;
        } else {
            $.amountOwedToOriginator = 0;
        }
        $.reserve = $.reserve - amount;

        require(checkMinFirstLost(), 'MinFirstLoss is not satisfied');
        require(
            IERC20Upgradeable(underlyingCurrency()).transferFrom(pot(), _msgSender(), amount),
            'SecuritizationPool: Transfer failed'
        );
        emit Withdraw(_msgSender(), amount);
    }

    // function tgeAddress() public view override(ISecuritizationTGE, SecuritizationPoolStorage) returns (address) {
    //     return super.tgeAddress();
    // }

    // function secondTGEAddress() public view override(ISecuritizationTGE, SecuritizationPoolStorage) returns (address) {
    //     return super.secondTGEAddress();
    // }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(ERC165Upgradeable, SecuritizationAccessControl, SecuritizationPoolStorage)
        returns (bool)
    {
        return interfaceId == type(ISecuritizationTGE).interfaceId || super.supportsInterface(interfaceId);
    }

    function pause() public virtual {
        registry().requirePoolAdminOrOwner(address(this), _msgSender());
        _pause();
    }

    function unpause() public virtual {
        registry().requirePoolAdminOrOwner(address(this), _msgSender());
        _unpause();
    }

    function getFunctionSignatures()
        public
        view
        virtual
        override(SecuritizationAccessControl, SecuritizationPoolStorage)
        returns (bytes4[] memory)
    {
        bytes4[] memory _functionSignatures = new bytes4[](23);

        _functionSignatures[0] = this.termLengthInSeconds.selector;
        _functionSignatures[1] = this.setPot.selector;
        _functionSignatures[2] = this.increaseReserve.selector;
        _functionSignatures[3] = this.decreaseReserve.selector;
        _functionSignatures[4] = this.sotToken.selector;
        _functionSignatures[5] = this.jotToken.selector;
        _functionSignatures[6] = this.underlyingCurrency.selector;
        _functionSignatures[7] = this.paidPrincipalAmountSOT.selector;
        _functionSignatures[8] = this.paidPrincipalAmountSOTByInvestor.selector;
        _functionSignatures[9] = this.reserve.selector;
        _functionSignatures[10] = this.principalAmountSOT.selector;
        _functionSignatures[11] = this.interestRateSOT.selector;
        _functionSignatures[12] = this.minFirstLossCushion.selector;
        _functionSignatures[13] = this.totalAssetRepaidCurrency.selector;
        _functionSignatures[14] = this.injectTGEAddress.selector;
        _functionSignatures[15] = this.increaseTotalAssetRepaidCurrency.selector;
        _functionSignatures[16] = this.redeem.selector;
        _functionSignatures[17] = this.hasFinishedRedemption.selector;
        _functionSignatures[18] = this.setInterestRateForSOT.selector;
        _functionSignatures[19] = this.claimCashRemain.selector;
        _functionSignatures[20] = this.startCycle.selector;
        _functionSignatures[21] = this.withdraw.selector;
        _functionSignatures[22] = this.supportsInterface.selector;

        return _functionSignatures;
    }
}
