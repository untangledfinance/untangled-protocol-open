// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.19;

import "./interest.sol";
import "./auth.sol";
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';

contract Pile is Auth, Interest, Initializable {
    /// @notice stores all needed information of an interest rate group
    struct Rate {
        // total debt of all loans with this rate
        uint256 pie;
        // accumlated rate index over time
        uint256 chi;
        // interest rate per second
        uint256 ratePerSecond;
        // last time the rate was accumulated
        uint48 lastUpdated;
        // fixed rate applied to each loan of the group
        uint256 fixedRate;
    }

    /// @notice Interest Rate Groups are identified by a `uint` and stored in a mapping
    mapping(uint256 => Rate) public rates;

    mapping(uint256 => uint256) public pie;

    /// @notice mapping from loan => rate
    mapping(uint256 => uint256) public loanRates;

    /// Events
    event IncreaseDebt(uint256 indexed loan, uint256 currencyAmount);
    event DecreaseDebt(uint256 indexed loan, uint256 currencyAmount);
    event SetRate(uint256 indexed loan, uint256 rate);
    event ChangeRate(uint256 indexed loan, uint256 newRate);
    event File(bytes32 indexed what, uint256 rate, uint256 value);

    function initialize(address _pool) public initializer {
        // pre-definition for loans without interest rates
        rates[0].chi = ONE;
        rates[0].ratePerSecond = ONE;

        wards[_pool] = 1;
        emit Rely(msg.sender);
    }

    /// @notice file manages different state configs for the pile
    /// only a ward can call this function
    /// @param what what config to change
    /// @param rate the interest rate group
    /// @param value the value to change
    function file(bytes32 what, uint256 rate, uint256 value) external auth {
        if (what == "rate") {
            require(value != 0, "rate-per-second-can-not-be-0");
            if (rates[rate].chi == 0) {
                rates[rate].chi = ONE;
                rates[rate].lastUpdated = uint48(block.timestamp);
            } else {
                drip(rate);
            }
            rates[rate].ratePerSecond = value;
        } else if (what == "fixedRate") {
            rates[rate].fixedRate = value;
        } else {
            revert("unknown parameter");
        }

        emit File(what, rate, value);
    }

    function incDebt(uint256 loan, uint256 currencyAmount) external auth {
        uint256 rate = loanRates[loan];
        require(block.timestamp == rates[rate].lastUpdated, "rate-group-not-updated");
        currencyAmount = safeAdd(currencyAmount, rmul(currencyAmount, rates[rate].fixedRate));
        uint256 pieAmount = toPie(rates[rate].chi, currencyAmount);

        pie[loan] = safeAdd(pie[loan], pieAmount);
        rates[rate].pie = safeAdd(rates[rate].pie, pieAmount);

        emit IncreaseDebt(loan, currencyAmount);
    }

    function decDebt(uint256 loan, uint256 currencyAmount) external auth {
        uint256 rate = loanRates[loan];
        require(block.timestamp == rates[rate].lastUpdated, "rate-group-not-updated");
        uint256 pieAmount = toPie(rates[rate].chi, currencyAmount);

        pie[loan] = safeSub(pie[loan], pieAmount);
        rates[rate].pie = safeSub(rates[rate].pie, pieAmount);

        emit DecreaseDebt(loan, currencyAmount);
    }

    function debt(uint256 loan) external view returns (uint256 loanDebt) {
        uint256 rate_ = loanRates[loan];
        uint256 chi_ = rates[rate_].chi;
        if (block.timestamp >= rates[rate_].lastUpdated) {
            chi_ = chargeInterest(rates[rate_].chi, rates[rate_].ratePerSecond, rates[rate_].lastUpdated);
        }
        return toAmount(chi_, pie[loan]);
    }

    function rateDebt(uint256 rate) external view returns (uint256 totalDebt) {
        uint256 chi_ = rates[rate].chi;
        uint256 pie_ = rates[rate].pie;

        if (block.timestamp >= rates[rate].lastUpdated) {
            chi_ = chargeInterest(rates[rate].chi, rates[rate].ratePerSecond, rates[rate].lastUpdated);
        }
        return toAmount(chi_, pie_);
    }

    function setRate(uint256 loan, uint256 rate) external auth {
        require(pie[loan] == 0, "non-zero-debt");
        // rate category has to be initiated
        require(rates[rate].chi != 0, "rate-group-not-set");
        loanRates[loan] = rate;
        emit SetRate(loan, rate);
    }

    function changeRate(uint256 loan, uint256 newRate) external auth {
        require(rates[newRate].chi != 0, "rate-group-not-set");
        uint256 currentRate = loanRates[loan];
        drip(currentRate);
        drip(newRate);
        uint256 pie_ = pie[loan];
        uint256 debt_ = toAmount(rates[currentRate].chi, pie_);
        rates[currentRate].pie = safeSub(rates[currentRate].pie, pie_);
        pie[loan] = toPie(rates[newRate].chi, debt_);
        rates[newRate].pie = safeAdd(rates[newRate].pie, pie[loan]);
        loanRates[loan] = newRate;
        emit ChangeRate(loan, newRate);
    }

    function accrue(uint256 loan) external {
        drip(loanRates[loan]);
    }

    function drip(uint256 rate) public {
        if (block.timestamp >= rates[rate].lastUpdated) {
            (uint256 chi,) =
                compounding(rates[rate].chi, rates[rate].ratePerSecond, rates[rate].lastUpdated, rates[rate].pie);
            rates[rate].chi = chi;
            rates[rate].lastUpdated = uint48(block.timestamp);
        }
    }

    uint256[50] private __gap;
}
