// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '../../../base/UntangledBase.sol';
import '../../../interfaces/ISecuritizationPool.sol';
import '../../../libraries/ConfigHelper.sol';
import '../../../interfaces/INoteToken.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

abstract contract Crowdsale is UntangledBase {
    using ConfigHelper for Registry;

    event UpdateTotalCap(uint256 totalCap);

    Registry public registry;

    // decimal calculating for rate
    uint256 public constant RATE_SCALING_FACTOR = 10**4;

    /// @dev Pool address which this sale belongs to
    address public pool;

    /// @dev The token being sold
    address public token;
    /// @dev The token being sold
    address public currency;

    // How many token units a buyer gets per currency.
    uint256 public rate; // support by RATE_SCALING_FACTOR decimal numbers
    bool public hasStarted;

    /// @dev Amount of currency raised
    uint256 public currencyRaised;
    /// @dev Amount of token raised
    uint256 public tokenRaised;

    /// @dev Target raised currency amount
    uint256 public totalCap;

    mapping(address => uint256) public currencyRaisedByInvestor;

    event TokensPurchased(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);

    function __Crowdsale__init(
        Registry _registry,
        address _pool,
        address _token,
        address _currency
    ) internal onlyInitializing {
        __UntangledBase__init_unchained(_msgSender());
        registry = _registry;
        pool = _pool;
        token = _token;
        currency = _currency;
    }

    modifier securitizationPoolRestricted() {
        require(_msgSender() == pool, 'Crowdsale: Caller must be pool');
        _;
    }

    modifier smpRestricted() {
        require(
            _msgSender() == address(registry.getSecuritizationManager()),
            'Crowdsale: Caller must be securitization manager'
        );
        _;
    }

    /// @notice add funding amount to be added to the total cap
    function addFunding(uint256 additionalCap) public nonReentrant whenNotPaused {
        require(
            hasRole(OWNER_ROLE, _msgSender()) || _msgSender() == address(registry.getSecuritizationManager()),
            'Crowdsale: caller must be owner or pool'
        );
        require(additionalCap > 0, 'Crowdsale: total cap is 0');

        totalCap = additionalCap + totalCap;

        emit UpdateTotalCap(totalCap);
    }

    /// @notice Sets the rate variable to the new rate
    function _newSaleRound(uint256 newRate) internal {
        require(!hasStarted, 'Crowdsale: Sale round overflow');

        hasStarted = true;
        rate = newRate;
    }

    /// @notice  Allows users to buy note token
    /// @param payee pay for purchase
    /// @param beneficiary wallet receives note token
    /// @param currencyAmount amount of currency used for purchase
    function buyTokens(
        address payee,
        address beneficiary,
        uint256 currencyAmount
    ) external whenNotPaused nonReentrant smpRestricted returns (uint256) {
        uint256 tokenAmount = getTokenAmount(currencyAmount);

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

    /// @notice Check if the total amount of currency raised is equal to the total cap
    function isDistributedFully() public view returns (bool) {
        return currencyRaised == totalCap;
    }

    /// @notice Retrieves the remaining token balance held by the crowdsale contract
    function getTokenRemainAmount() public view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /// @notice Calculates the remaining amount of currency available for purchase
    function getCurrencyRemainAmount() public view virtual returns (uint256) {
        return totalCap - currencyRaised;
    }

    /// @notice Determines whether the current sale round is a long sale
    /// @dev This is an abstract function that needs to be implemented in derived contracts
    function isLongSale() public view virtual returns (bool);

    /// @notice Calculates the corresponding token amount based on the currency amount and the current rate
    /// @dev This is an abstract function that needs to be implemented in derived contracts
    function getTokenAmount(uint256 currencyAmount) public view virtual returns (uint256);

    /// @notice Requires that the currency amount does not exceed the total cap
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

    /// @dev Mints and delivers tokens to the beneficiary
    function _deliverTokens(address beneficiary, uint256 tokenAmount) internal {
        INoteToken(token).mint(beneficiary, tokenAmount);
    }

    /// @dev Burns and delivers tokens to the beneficiary
    function _ejectTokens(uint256 tokenAmount) internal {
        INoteToken(token).burn(tokenAmount);
    }

    function _processPurchase(address beneficiary, uint256 tokenAmount) internal {
        _deliverTokens(beneficiary, tokenAmount);
    }

    /// @dev Transfers the currency from the payer to the crowdsale contract
    function _claimPayment(address payee, uint256 currencyAmount) internal {
        require(
            IERC20(currency).transferFrom(payee, address(this), currencyAmount),
            'Fail to transfer currency from payee to contract'
        );
    }

    // function getTokenAmount(uint256 currencyAmount) public view returns (uint256) {
    //     require(rate > 0, 'Crowdsale: rate is 0');
    //     uint256 TEN = 10;
    //     return
    //         (currencyAmount * rate * TEN**ERC20(token).decimals()) /
    //         (RATE_SCALING_FACTOR * TEN**ERC20(currency).decimals());
    // }

    /// @dev Transfers the currency funds from the crowdsale contract to the specified beneficiary
    function _forwardFunds(address beneficiary, uint256 currencyAmount) internal {
        require(IERC20(currency).transfer(beneficiary, currencyAmount), 'Fail to transfer currency to Beneficiary');
    }

    /// @dev Sets the total cap to the specified amount
    function _setTotalCap(uint256 cap) internal {
        require(cap > 0, 'Crowdsale: cap is 0');
        require(cap >= currencyRaised, 'Crowdsale: cap is bellow currency raised');

        totalCap = cap;

        emit UpdateTotalCap(totalCap);
    }

    /// @notice Checks if the total amount of currency raised is greater than or equal to the total cap
    function totalCapReached() public view returns (bool) {
        return currencyRaised >= totalCap;
    }

    /// @notice Checks if the sum of the current currency raised and the specified currency amount is less than or equal to the total cap
    function isUnderTotalCap(uint256 currencyAmount) public view returns (bool) {
        return currencyRaised + currencyAmount <= totalCap;
    }
}
