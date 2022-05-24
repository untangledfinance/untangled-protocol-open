// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../../../base/UntangledBase.sol';
import '../../../interfaces/ISecuritizationPool.sol';
import '../../../libraries/ConfigHelper.sol';
import '../../../interfaces/INoteToken.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract Crowdsale is UntangledBase {
    using ConfigHelper for Registry;

    Registry public registry;

    // decimal calculating for rate
    uint256 public constant RATE_SCALING_FACTOR = 10**4;

    address public pool;

    // The token being sold
    address public token;
    // The token for pay
    address public currency;

    // How many token units a buyer gets per currency.
    uint256 public rate; // support by RATE_SCALING_FACTOR decimal numbers
    bool public hasStarted;

    // Amount of currency raised
    uint256 public currencyRaised;
    uint256 public tokenRaised;

    bool internal initialized;

    uint256 public totalCap;

    mapping(address => uint256) public currencyRaisedByInvestor;

    event TokensPurchased(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);

    function __Crowdsale__init() internal onlyInitializing {
        __UntangledBase__init_unchained(_msgSender());
    }

    modifier securitizationPoolRestricted() {
        require(_msgSender() == pool, 'Crowdsale: Caller must be pool');
        _;
    }

    modifier smpRestricted() {
        require(_msgSender() == address(registry.getSecuritizationManager()), 'Crowdsale: Caller must be pool');
        _;
    }

    function addFunding(uint256 additionalCap) public whenNotPaused nonReentrant onlyRole(OWNER_ROLE) {
        require(additionalCap > 0, 'Crowdsale: total cap is 0');

        totalCap = additionalCap + totalCap;
    }

    function newSaleRound(uint256 newRate) internal {
        require(!hasStarted, 'Crowdsale: Sale round overflow');

        hasStarted = true;
        rate = newRate;
    }

    function buyTokens(
        address payee,
        address beneficiary,
        uint256 currencyAmount
    ) external whenNotPaused nonReentrant smpRestricted returns (uint256) {
        uint256 tokenAmount = isLongSale() ? getLongSaleTokenAmount(currencyAmount) : _getTokenAmount(currencyAmount);

        _preValidatePurchase(beneficiary, currencyAmount, tokenAmount);

        // update state
        currencyRaised += currencyAmount;
        currencyRaisedByInvestor[beneficiary] += currencyAmount;

        tokenRaised += tokenAmount;

        _claimPayment(payee, currencyAmount);
        _processPurchase(beneficiary, tokenAmount);
        emit TokensPurchased(_msgSender(), beneficiary, currencyAmount, tokenAmount);

        _forwardFunds(ISecuritizationPool(pool).pot(), currencyAmount);

        return tokenAmount;
    }

    function isDistributedFully() public view returns (bool) {
        return currencyRaised == totalCap;
    }

    function getTokenRemainAmount() public view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function getCurrencyRemainAmount() public view virtual returns (uint256) {
        return totalCap - currencyRaised;
    }

    function isLongSale() public view virtual returns (bool);

    function getLongSaleTokenAmount(uint256 currencyAmount) public view virtual returns (uint256);

    function _defaultPreValidatePurchase(
        address beneficiary,
        uint256 currencyAmount,
        uint256 tokenAmount
    ) internal view {
        require(beneficiary != address(0), 'Crowdsale: beneficiary is zero address');
        //        require(currencyAmount != 0, "currency amount is 0");
        require(tokenAmount != 0, 'Crowdsale: token amount is 0');
        require(isUnderTotalCap(currencyAmount), 'Crowdsale: cap exceeded');
    }

    function _preValidatePurchase(
        address beneficiary,
        uint256 currencyAmount,
        uint256 tokenAmount
    ) internal view virtual {
        _defaultPreValidatePurchase(beneficiary, currencyAmount, tokenAmount);
    }

    function _deliverTokens(address beneficiary, uint256 tokenAmount) internal {
        INoteToken(token).mint(beneficiary, tokenAmount);
    }

    function _ejectTokens(uint256 tokenAmount) internal {
        INoteToken(token).burn(tokenAmount);
    }

    function _processPurchase(address beneficiary, uint256 tokenAmount) internal {
        _deliverTokens(beneficiary, tokenAmount);
    }

    function _claimPayment(address payee, uint256 currencyAmount) internal {
        IERC20(currency).transferFrom(payee, address(this), currencyAmount);
    }

    function _getTokenAmount(uint256 currencyAmount) public view returns (uint256) {
        require(rate > 0, 'Crowdsale: rate is 0');
        uint256 TEN = 10;
        return
            (currencyAmount * rate * TEN**ERC20(token).decimals()) /
            (RATE_SCALING_FACTOR * TEN**ERC20(currency).decimals());
    }

    function _getCurrencyAmount(uint256 tokenAmount) internal view returns (uint256) {
        if (rate == 0) return 0;
        uint256 TEN = 10;
        return
            (tokenAmount * RATE_SCALING_FACTOR * TEN**ERC20(currency).decimals()) /
            (rate * TEN**ERC20(token).decimals());
    }

    function _forwardFunds(address beneficiary, uint256 currencyAmount) internal {
        IERC20(currency).transfer(beneficiary, currencyAmount);
    }

    function setTotalCap(uint256 cap) internal {
        require(cap > 0, 'Crowdsale: cap is 0');
        require(cap >= currencyRaised, 'Crowdsale: cap is bellow currency raised');

        totalCap = cap;
    }

    function totalCapReached() public view returns (bool) {
        return currencyRaised >= totalCap;
    }

    function isUnderTotalCap(uint256 currencyAmount) public view returns (bool) {
        return currencyRaised + currencyAmount <= totalCap;
    }
}
