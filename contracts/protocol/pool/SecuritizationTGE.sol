// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

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

abstract contract SecuritizationTGE is
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    RegistryInjection,
    SecuritizationAccessControl,
    ISecuritizationTGE
{
    using ConfigHelper for Registry;

    CycleState public override state;

    address public override tgeAddress;
    address public override secondTGEAddress;
    address public override sotToken;
    address public override jotToken;
    address public override underlyingCurrency;
    uint256 public override reserve; // Money in pool
    uint32 public override minFirstLossCushion;

    uint64 public override openingBlockTimestamp;
    uint64 public override termLengthInSeconds;

    // by default it is address(this)
    address public override pot;

    // for base (sell-loan) operation
    uint256 public override principalAmountSOT;
    uint256 public override paidPrincipalAmountSOT;
    uint32 public override interestRateSOT; // Annually, support 4 decimals num

    uint256 public override totalAssetRepaidCurrency;

    mapping(address => uint256) public override paidPrincipalAmountSOTByInvestor;

    modifier onlyIssuingTokenStage() {
        require(state != CycleState.OPEN && state != CycleState.CLOSED, 'Not in issuing token stage');
        _;
    }

    modifier finishRedemptionValidator() {
        require(hasFinishedRedemption(), 'SecuritizationPool: Redemption has not finished');
        _;
    }

    modifier notClosingStage() {
        require(!isClosedState(), 'SecuritizationPool: Pool in closed state');
        _;
    }

    function isClosedState() public view override returns (bool) {
        return state == CycleState.CLOSED;
    }

    /// @inheritdoc ISecuritizationTGE
    function injectTGEAddress(
        address _tgeAddress,
        address _tokenAddress,
        Configuration.NOTE_TOKEN_TYPE _noteType
    ) external override whenNotPaused onlyIssuingTokenStage {
        registry().requireSecuritizationManager(_msgSender());
        require(_tgeAddress != address(0x0) && _tokenAddress != address(0x0), 'SecuritizationPool: Address zero');

        if (_noteType == Configuration.NOTE_TOKEN_TYPE.SENIOR) {
            tgeAddress = _tgeAddress;
            sotToken = _tokenAddress;
        } else {
            secondTGEAddress = _tgeAddress;
            jotToken = _tokenAddress;
        }
        state = CycleState.CROWDSALE;

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
        if (sotToken == notesToken) {
            paidPrincipalAmountSOTByInvestor[usr] += currencyAmount;
            emit UpdatePaidPrincipalAmountSOTByInvestor(usr, currencyAmount);
        }

        reserve = reserve - currencyAmount;

        if (tokenAmount > 0) {
            ERC20BurnableUpgradeable(notesToken).burn(tokenAmount);
        }

        require(checkMinFirstLost(), 'MinFirstLoss is not satisfied');
        require(
            IERC20Upgradeable(underlyingCurrency).transferFrom(pot, usr, currencyAmount),
            'SecuritizationPool: currency-transfer-failed'
        );

        emit UpdateReserve(reserve);
    }

    function checkMinFirstLost() public view virtual returns (bool) {
        ISecuritizationPoolValueService poolService = registry().getSecuritizationPoolValueService();
        return minFirstLossCushion <= poolService.getJuniorRatio(address(this));
    }

    // Increase by value
    function increaseTotalAssetRepaidCurrency(uint256 amount) external virtual override whenNotPaused {
        registry().requireLoanRepaymentRouter(_msgSender());
        reserve = reserve + amount;
        totalAssetRepaidCurrency = totalAssetRepaidCurrency + amount;

        emit UpdateReserve(reserve);
    }

    function hasFinishedRedemption() public view override returns (bool) {
        if (sotToken != address(0)) {
            require(IERC20Upgradeable(sotToken).totalSupply() == 0, 'SecuritizationPool: SOT still remain');
        }
        if (jotToken != address(0)) {
            require(IERC20Upgradeable(jotToken).totalSupply() == 0, 'SecuritizationPool: JOT still remain');
        }

        return true;
    }

    function setPot(address _pot) external override whenNotPaused nonReentrant notClosingStage {
        registry().requirePoolAdminOrOwner(address(this), _msgSender());

        require(pot != _pot, 'SecuritizationPool: Same address with current pot');
        pot = _pot;
        if (_pot == address(this)) {
            require(
                IERC20Upgradeable(underlyingCurrency).approve(pot, type(uint256).max),
                'SecuritizationPool: Pot not approved'
            );
        }
        registry().getSecuritizationManager().registerPot(pot);
    }

    function increaseReserve(uint256 currencyAmount) external override whenNotPaused {
        require(
            _msgSender() == address(registry().getSecuritizationManager()) ||
                _msgSender() == address(registry().getDistributionOperator()),
            'SecuritizationPool: Caller must be SecuritizationManager or DistributionOperator'
        );
        reserve = reserve + currencyAmount;
        require(checkMinFirstLost(), 'MinFirstLoss is not satisfied');

        emit UpdateReserve(reserve);
    }

    function decreaseReserve(uint256 currencyAmount) external override whenNotPaused {
        require(
            _msgSender() == address(registry().getSecuritizationManager()) ||
                _msgSender() == address(registry().getDistributionOperator()),
            'SecuritizationPool: Caller must be SecuritizationManager or DistributionOperator'
        );
        reserve = reserve - currencyAmount;
        require(checkMinFirstLost(), 'MinFirstLoss is not satisfied');

        emit UpdateReserve(reserve);
    }

    function setInterestRateForSOT(uint32 _interestRateSOT) external override whenNotPaused {
        require(_msgSender() == tgeAddress, 'SecuritizationPool: Only tge can update interest');
        interestRateSOT = _interestRateSOT;
        emit UpdateInterestRateSOT(_interestRateSOT);
    }

    // After closed pool and redeem all not -> get remain cash to recipient wallet
    function claimCashRemain(
        address recipientWallet
    ) external override whenNotPaused onlyOwner finishRedemptionValidator {
        IERC20Upgradeable currency = IERC20Upgradeable(underlyingCurrency);
        require(
            currency.transferFrom(pot, recipientWallet, currency.balanceOf(pot)),
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
}
