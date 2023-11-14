// SPDX-License-Identifier: AGPL-3.0-only
// TODO License
pragma solidity 0.8.19;

import "./auth.sol";
import {Discounting} from "./discounting.sol";
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import "../../libraries/ConfigHelper.sol";
import "../../libraries/UnpackLoanParamtersLib.sol";

// TODO A @KhanhPham Deploy this
contract PoolNAV is Auth, Discounting, Initializable {
    using ConfigHelper for Registry;

    /// @notice details of the underlying collateral
    struct NFTDetails {
        uint128 nftValues;
        uint128 futureValue;
        uint128 maturityDate;
        uint128 risk;
    }

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
    }

    address public pool;
    Registry public registry;

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

    uint256 public loanCount;
    mapping(uint256 => uint256) public balances;
    uint256 public balance;

    /// @notice details of the loan
    struct LoanDetails {
        uint128 borrowed;
        // only auth calls can move loan into different writeOff group
        bool authWriteOff;
    }

    /// @notice details of the write off group
    struct WriteOffGroup {
        // denominated in (10^27)
        uint128 percentage;
        // amount of days after the maturity days that the writeoff group can be applied by default
        uint128 overdueDays;
        // denominated in (10^27)
        uint128 penalty;
        uint128 riskIndex;
    }

    // nft => details
    mapping(bytes32 => NFTDetails) public details;
    // loan => details
    mapping(uint256 => LoanDetails) public loanDetails;
    // timestamp => bucket
    mapping(uint256 => uint256) public buckets;

    WriteOffGroup[] public writeOffGroups;

    // Write-off groups will be added as rate groups to the pile with their index
    // in the writeOffGroups array + this number
    uint256 public constant WRITEOFF_RATE_GROUP_START = 1000 * ONE;
    uint256 public constant INTEREST_RATE_SCALING_FACTOR_PERCENT = 10 ** 4;
    uint256 public constant ONE_HUNDRED_PERCENT = 100 * INTEREST_RATE_SCALING_FACTOR_PERCENT;

    // Discount rate applied on every asset's fv depending on its maturityDate.
    // The discount decreases with the maturityDate approaching.
    // denominated in (10^27)
    uint256 public discountRate;

    // latestNAV is calculated in case of borrows & repayments between epoch executions.
    // It decreases/increases the NAV by the repaid/borrowed amount without running the NAV calculation routine.
    // This is required for more accurate Senior & JuniorAssetValue estimations between epochs
    uint256 public latestNAV;
    uint256 public latestDiscount;
    uint256 public lastNAVUpdate;

    // overdue loans are loans which passed the maturity date but are not written-off
    uint256 public overdueLoans;

    // events
    event Depend(bytes32 indexed name, address addr);
    event SetLoanMaturity(bytes32 nftID_, uint256 maturityDate_);
    event WriteOff(uint256 indexed loan, uint256 indexed writeOffGroupsIndex, bool override_);
    event AddLoan(uint256 indexed loan, uint256 principalAmount, uint256 maturityDate);

    function getRiskScoreByIdx(uint256 idx) private view returns (ISecuritizationPool.RiskScore memory) {
        ISecuritizationPool securitizationPool = ISecuritizationPool(pool);
        require(address(securitizationPool) != address(0), 'Pool was not deployed');
        if (idx == 0 || securitizationPool.getRiskScoresLength() == 0) {
            // Default risk score
            return ISecuritizationPool.RiskScore({
                daysPastDue: 0,
                advanceRate: 1000000,
                penaltyRate: 0,
                interestRate: 0,
                probabilityOfDefault: 0,
                lossGivenDefault: 0,
                gracePeriod: 0,
                collectionPeriod: 0,
                writeOffAfterGracePeriod: 0,
                writeOffAfterCollectionPeriod: 0,
                discountRate: 0
            });
        }
        // Because risk score upload = risk score index onchain + 1
        idx = idx - 1;
        (
            uint32 daysPastDue,
            uint32 advanceRate,
            uint32 penaltyRate,
            uint32 interestRate,
            uint32 probabilityOfDefault,
            uint32 lossGivenDefault,
            uint32 gracePeriod,
            uint32 collectionPeriod,
            uint32 writeOffAfterGracePeriod,
            uint32 writeOffAfterCollectionPeriod,
            uint32 discountRate
        ) = securitizationPool.riskScores(idx);

        return
            ISecuritizationPool.RiskScore({
            daysPastDue: daysPastDue,
            advanceRate: advanceRate,
            penaltyRate: penaltyRate,
            interestRate: interestRate,
            probabilityOfDefault: probabilityOfDefault,
            lossGivenDefault: lossGivenDefault,
            gracePeriod: gracePeriod,
            collectionPeriod: collectionPeriod,
            writeOffAfterGracePeriod: writeOffAfterGracePeriod,
            writeOffAfterCollectionPeriod: writeOffAfterCollectionPeriod,
            discountRate: discountRate
        });
    }

    function addLoan(uint256 loan) external auth {
        UnpackLoanParamtersLib.InterestParams memory loanParam = registry.getLoanInterestTermsContract().unpackParamsForAgreementID(bytes32(loan));
        bytes32 _tokenId = bytes32(loan);
        ILoanRegistry.LoanEntry memory loanEntry = registry.getLoanRegistry().getEntry(_tokenId);
        ISecuritizationPool.RiskScore memory riskParam = getRiskScoreByIdx(loanEntry.riskScore);
        uint256 principalAmount = loanParam.principalAmount;
        if (loanEntry.assetPurpose == Configuration.ASSET_PURPOSE.PLEDGE) {
            principalAmount = (principalAmount * riskParam.advanceRate) / (ONE_HUNDRED_PERCENT);
        }

        loanCount++;
        setLoanMaturityDate(_tokenId, loanParam.termEndUnixTimestamp);
        uint256 _convertedInterestRate = ONE + loanParam.interestRate * ONE / (100 * INTEREST_RATE_SCALING_FACTOR_PERCENT * 365 days);
        if (rates[_convertedInterestRate].ratePerSecond == 0) { // If interest rate is not set
            file("rate", _convertedInterestRate, _convertedInterestRate);
        }
        setRate(loan, _convertedInterestRate);
        accrue(loan);

        balances[loan] = safeAdd(balances[loan], principalAmount);
        balance = safeAdd(balance, principalAmount);

        // increase NAV
        borrow(loan, principalAmount);
        incDebt(loan, principalAmount);

        emit AddLoan(loan, principalAmount, loanParam.termEndUnixTimestamp);
    }

    /// @notice getter function for the maturityDate
    /// @param nft_ the id of the nft based on the hash of registry and tokenId
    /// @return maturityDate_ the maturityDate of the nft
    function maturityDate(bytes32 nft_) public view returns (uint256 maturityDate_) {
        return uint256(details[nft_].maturityDate);
    }
    /// @notice getter function for the risk group
    /// @param nft_ the id of the nft based on the hash of registry and tokenId
    /// @return risk_ the risk group of the nft

    function risk(bytes32 nft_) public view returns (uint256 risk_) {
        return uint256(details[nft_].risk);
    }
    /// @notice getter function for the nft value
    /// @param nft_ the id of the nft based on the hash of registry and tokenId
    /// @return nftValue_ the value of the nft

    function nftValues(bytes32 nft_) public view returns (uint256 nftValue_) {
        return uint256(details[nft_].nftValues);
    }

    /// @notice getter function for the future value
    /// @param nft_ the id of the nft based on the hash of registry and tokenId
    /// @return fv_ future value of the loan
    function futureValue(bytes32 nft_) public view returns (uint256 fv_) {
        return uint256(details[nft_].futureValue);
    }

    /// @notice getter function for the recovery rate PD
    /// @param riskID id of a risk group
    /// @return recoveryRatePD_ recovery rate PD of the risk group
    function recoveryRatePD(uint256 riskID, uint256 termLength) public view returns (uint256 recoveryRatePD_) {
        ISecuritizationPool.RiskScore memory riskParam = getRiskScoreByIdx(riskID);
        return ONE - (ONE * riskParam.probabilityOfDefault * riskParam.lossGivenDefault * termLength) / (ONE_HUNDRED_PERCENT * ONE_HUNDRED_PERCENT * 365 days);
    }

    /// @notice getter function for the borrowed amount
    /// @param loan id of a loan
    /// @return borrowed_ borrowed amount of the loan
    function borrowed(uint256 loan) public view returns (uint256 borrowed_) {
        return uint256(loanDetails[loan].borrowed);
    }

    function initialize(Registry _registry, address _pool) public initializer {
        registry = _registry;
        wards[_pool] = 1;
        pool = _pool;
        lastNAVUpdate = uniqueDayTimestamp(block.timestamp);

        // pre-definition for loans without interest rates
        rates[0].chi = ONE;
        rates[0].ratePerSecond = ONE;

        // Default discount rate
        discountRate = ONE;

        emit Rely(_pool);
    }

    /// @notice converts a uint256 to uint128
    /// @param value the value to be converted
    /// @return converted value to uint128
    function toUint128(uint256 value) internal pure returns (uint128 converted) {
        require(value <= type(uint128).max, "SafeCast: value doesn't fit in 128 bits");
        return uint128(value);
    }

    function setLoanMaturityDate(bytes32 nftID_, uint256 maturityDate_) public auth {
        require((futureValue(nftID_) == 0), "can-not-change-maturityDate-outstanding-debt");
        details[nftID_].maturityDate = toUint128(uniqueDayTimestamp(maturityDate_));
        emit SetLoanMaturity(nftID_, maturityDate_);
    }

    /// @notice file allows governance to change parameters of the contract
    /// @param name name of the parameter
    /// @param value new value of the parameter
    function file(bytes32 name, uint256 value) public auth {
        if (name == "discountRate") {
            uint256 oldDiscountRate = discountRate;
            discountRate = ONE + value * ONE / (100 * INTEREST_RATE_SCALING_FACTOR_PERCENT * 365 days);
            // the nav needs to be re-calculated based on the new discount rate
            // no need to recalculate it if initialized the first time
            if (oldDiscountRate != 0) {
                reCalcNAV();
            }
        } else {
            revert("unknown config parameter");
        }
    }

    /// @notice file allows governance to change parameters of the contract
    /// @param name name of the parameter group
    /// @param writeOffPercentage_ the write off rate in percent
    /// @param overdueDays_ the number of days after which a loan is considered overdue
    function file(bytes32 name, uint256 rate_, uint256 writeOffPercentage_, uint256 overdueDays_, uint256 penaltyRate_, uint256 riskIndex) public auth {
        if (name == "writeOffGroup") {
            uint256 index = writeOffGroups.length;
            uint256 _convertedInterestRate = ONE + rate_ * ONE / (100 * INTEREST_RATE_SCALING_FACTOR_PERCENT * 365 days);
            uint256 _convertedWriteOffPercentage = ONE - writeOffPercentage_ * ONE / ONE_HUNDRED_PERCENT;
            uint256 _convertedPenaltyRate = ONE + penaltyRate_ * ONE / (100 * INTEREST_RATE_SCALING_FACTOR_PERCENT * 365 days);
            uint256 _convertedOverdueDays = overdueDays_ / 1 days;
            writeOffGroups.push(WriteOffGroup(toUint128(_convertedWriteOffPercentage), toUint128(_convertedOverdueDays), toUint128(_convertedPenaltyRate), toUint128(riskIndex)));
            file("rate", safeAdd(WRITEOFF_RATE_GROUP_START, index), _convertedInterestRate);
        } else {
            revert("unknown name");
        }
    }

    /// @notice file manages different state configs for the pile
    /// only a ward can call this function
    /// @param what what config to change
    /// @param rate the interest rate group
    /// @param value the value to change
    function file(bytes32 what, uint256 rate, uint256 value) public auth {
        if (what == "rate") {
            require(value != 0, "rate-per-second-can-not-be-0");
            if (rates[rate].chi == 0) {
                rates[rate].chi = ONE;
                rates[rate].lastUpdated = uint48(block.timestamp);
            } else {
                drip(rate);
            }
            rates[rate].ratePerSecond = value;
        } else {
            revert("unknown parameter");
        }

    }

    /// @notice borrow updates the NAV for a new borrowed loan
    /// @param loan the id of the loan
    /// @param amount the amount borrowed
    /// @return navIncrease the increase of the NAV impacted by the new borrow
    function borrow(uint256 loan, uint256 amount) private returns (uint256 navIncrease) {
        uint256 nnow = uniqueDayTimestamp(block.timestamp);
        bytes32 nftID_ = nftID(loan);
        uint256 maturityDate_ = maturityDate(nftID_);

        require(maturityDate_ > nnow, "maturity-date-is-not-in-the-future");

        if (nnow > lastNAVUpdate) {
            calcUpdateNAV();
        }

        // calculate amount including fixed fee if applicatable
        Rate memory _rate = rates[loanRates[loan]];

        // calculate future value FV
        ILoanRegistry.LoanEntry memory loanEntry = registry.getLoanRegistry().getEntry(bytes32(loan));
        uint256 fv =
                        calcFutureValue(_rate.ratePerSecond, amount, maturityDate_, recoveryRatePD(loanEntry.riskScore, loanEntry.expirationTimestamp - loanEntry.issuanceBlockTimestamp));
        details[nftID_].futureValue = toUint128(safeAdd(futureValue(nftID_), fv));

        // add future value to the bucket of assets with the same maturity date
        buckets[maturityDate_] = safeAdd(buckets[maturityDate_], fv);

        // increase borrowed amount for future ceiling computations
        loanDetails[loan].borrowed = toUint128(safeAdd(borrowed(loan), amount));

        // return increase NAV amount
        navIncrease = calcDiscount(discountRate, fv, nnow, maturityDate_);

        latestDiscount = safeAdd(latestDiscount, navIncrease);
        latestNAV = safeAdd(latestNAV, navIncrease);
        return navIncrease;
    }

    /// @notice repay updates the NAV for a new repaid loan
    /// @param loan the id of the loan
    /// @param amount the amount repaid
    function repayLoan(uint256 loan, uint256 amount) external returns (uint256) {
        require(address(registry.getLoanRepaymentRouter()) == msg.sender, "not authorized");
        accrue(loan);
        uint256 nnow = uniqueDayTimestamp(block.timestamp);
        if (nnow > lastNAVUpdate) {
            calcUpdateNAV();
        }

        // In case of successful repayment the latestNAV is decreased by the repaid amount
        bytes32 nftID_ = nftID(loan);
        uint256 maturityDate_ = maturityDate(nftID_);


        uint256 _currentDebt = this.debt(loan);
        if (amount > _currentDebt) {
            amount = _currentDebt;
        }
        // case 1: repayment of a written-off loan
        if (isLoanWrittenOff(loan)) {
            // update nav with write-off decrease
            latestNAV = secureSub(
                latestNAV,
                rmul(amount, toUint128(writeOffGroups[loanRates[loan] - WRITEOFF_RATE_GROUP_START].percentage))
            );

            return amount;
        }
        uint256 _debt = safeSub(_currentDebt, amount); // Remaining
        uint256 preFV = futureValue(nftID_);
        // in case of partial repayment, compute the fv of the remaining debt and add to the according fv bucket
        uint256 fv = 0;
        uint256 fvDecrease = preFV;
        if (_debt != 0) {
            Rate memory _rate = rates[loanRates[loan]];
            ILoanRegistry.LoanEntry memory loanEntry = registry.getLoanRegistry().getEntry(nftID_);
            fv = calcFutureValue(_rate.ratePerSecond, _debt, maturityDate_, recoveryRatePD(loanEntry.riskScore, loanEntry.expirationTimestamp - loanEntry.issuanceBlockTimestamp));
            if (preFV >= fv) {
                fvDecrease = safeSub(preFV, fv);
            } else {
                fvDecrease = 0;
            }
        }

        details[nftID_].futureValue = toUint128(fv);
        // case 2: repayment of a loan before or on maturity date
        if (maturityDate_ >= nnow) {
            // remove future value decrease from bucket
            buckets[maturityDate_] = safeSub(buckets[maturityDate_], fvDecrease);
            uint256 discountDecrease = calcDiscount(discountRate, fvDecrease, nnow, maturityDate_);
            latestDiscount = secureSub(latestDiscount, discountDecrease);
            latestNAV = secureSub(latestNAV, discountDecrease);
        } else {
            // case 3: repayment of an overdue loan
            overdueLoans = safeSub(overdueLoans, fvDecrease);
            latestNAV = secureSub(latestNAV, fvDecrease);
        }
        decDebt(loan, amount);
        return amount;
    }

    /// @notice borrowEvent triggers a borrow event for a loan
    /// @param loan the id of the loan
    function borrowEvent(uint256 loan, uint256) public virtual auth {
        uint256 risk_ = risk(nftID(loan));

        // when issued every loan has per default interest rate of risk group 0.
        // correct interest rate has to be set on first borrow event
        if (loanRates[loan] != risk_) {
            // set loan interest rate to the one of the correct risk group
            setRate(loan, risk_);
        }
    }

    /// @notice writeOff writes off a loan if it is overdue
    /// @param loan the id of the loan
    function writeOff(uint256 loan) public {
        require(!loanDetails[loan].authWriteOff, "only-auth-write-off");

        bytes32 nftID_ = nftID(loan);
        uint256 maturityDate_ = maturityDate(nftID_);
        require(maturityDate_ > 0, "loan-does-not-exist");

        // can not write-off healthy loans
        uint256 nnow = uniqueDayTimestamp(block.timestamp);
        require(maturityDate_ < nnow, "maturity-date-in-the-future");
        // check the writeoff group based on the amount of days overdue
        uint256 writeOffGroupIndex_ = currentValidWriteOffGroup(loan);

        if (
            writeOffGroupIndex_ < type(uint128).max
                && loanRates[loan] != WRITEOFF_RATE_GROUP_START + writeOffGroupIndex_
        ) {
            _writeOff(loan, writeOffGroupIndex_, nftID_, maturityDate_);
            emit WriteOff(loan, writeOffGroupIndex_, false);
        }
    }

    /// @notice authorized call to write of a loan in a specific writeoff group
    /// @param loan the id of the loan
    /// @param writeOffGroupIndex_ the index of the writeoff group
    function overrideWriteOff(uint256 loan, uint256 writeOffGroupIndex_) public auth {
        // can not write-off healthy loans
        bytes32 nftID_ = nftID(loan);
        uint256 maturityDate_ = maturityDate(nftID_);
        uint256 nnow = uniqueDayTimestamp(block.timestamp);
        require(maturityDate_ < nnow, "maturity-date-in-the-future");

        if (loanDetails[loan].authWriteOff == false) {
            loanDetails[loan].authWriteOff = true;
        }
        _writeOff(loan, writeOffGroupIndex_, nftID_, maturityDate_);
        emit WriteOff(loan, writeOffGroupIndex_, true);
    }

    /// @notice internal function for the write off
    /// @param loan the id of the loan
    /// @param writeOffGroupIndex_ the index of the writeoff group
    /// @param nftID_ the nftID of the loan
    /// @param maturityDate_ the maturity date of the loan
    function _writeOff(uint256 loan, uint256 writeOffGroupIndex_, bytes32 nftID_, uint256 maturityDate_) internal {
        uint256 nnow = uniqueDayTimestamp(block.timestamp);
        // Ensure we have an up to date NAV
        if (nnow > lastNAVUpdate) {
            calcUpdateNAV();
        }

        uint256 latestNAV_ = latestNAV;

        // first time written-off
        if (isLoanWrittenOff(loan) == false) {
            uint256 fv = futureValue(nftID_);
            if (uniqueDayTimestamp(lastNAVUpdate) > maturityDate_) {
                // write off after the maturity date
                overdueLoans = secureSub(overdueLoans, fv);
                latestNAV_ = secureSub(latestNAV_, fv);
            } else {
                // write off before or on the maturity date
                buckets[maturityDate_] = safeSub(buckets[maturityDate_], fv);
                uint256 pv = rmul(fv, rpow(discountRate, safeSub(uniqueDayTimestamp(maturityDate_), nnow), ONE));
                latestDiscount = secureSub(latestDiscount, pv);
                latestNAV_ = secureSub(latestNAV_, pv);
            }
        }

        changeRate(loan, WRITEOFF_RATE_GROUP_START + writeOffGroupIndex_);
        latestNAV = safeAdd(latestNAV_, rmul(debt(loan), writeOffGroups[writeOffGroupIndex_].percentage));
    }

    /// @notice returns if a loan is written off
    /// @param loan the id of the loan
    function isLoanWrittenOff(uint256 loan) public view returns (bool) {
        return loanRates[loan] >= WRITEOFF_RATE_GROUP_START;
    }

    /// @notice calculates and returns the current NAV
    /// @return nav_ current NAV
    function currentNAV() public view returns (uint256 nav_) {
        (uint256 totalDiscount, uint256 overdue, uint256 writeOffs) = currentPVs();
        return safeAdd(totalDiscount, safeAdd(overdue, writeOffs));
    }

    /// @notice calculates the present value of the loans together with overdue and written off loans
    /// @return totalDiscount the present value of the loans
    /// @return overdue the present value of the overdue loans
    /// @return writeOffs the present value of the written off loans
    function currentPVs() public view returns (uint256 totalDiscount, uint256 overdue, uint256 writeOffs) {
        if (latestDiscount == 0) {
            // all loans are overdue or writtenOff
            return (0, overdueLoans, currentWriteOffs());
        }

        uint256 errPV = 0;
        uint256 nnow = uniqueDayTimestamp(block.timestamp);

        // find all new overdue loans since the last update
        // calculate the discount of the overdue loans which is needed
        // for the total discount calculation
        for (uint256 i = lastNAVUpdate; i < nnow; i = i + 1 days) {
            uint256 b = buckets[i];
            if (b != 0) {
                errPV = safeAdd(errPV, rmul(b, rpow(discountRate, safeSub(nnow, i), ONE)));
                overdue = safeAdd(overdue, b);
            }
        }

        return (
            // calculate current totalDiscount based on the previous totalDiscount (optimized calculation)
            // the overdue loans are incorrectly in this new result with their current PV and need to be removed
            secureSub(rmul(latestDiscount, rpow(discountRate, safeSub(nnow, lastNAVUpdate), ONE)), errPV),
            // current overdue loans not written off
            safeAdd(overdueLoans, overdue),
            // current write-offs loans
            currentWriteOffs()
        );
    }

    /// @notice returns the sum of all write off loans
    /// @return sum of all write off loans
    function currentWriteOffs() public view returns (uint256 sum) {
        for (uint256 i = 0; i < writeOffGroups.length; i++) {
            // multiply writeOffGroupDebt with the writeOff rate
            sum =
                safeAdd(sum, rmul(rateDebt(WRITEOFF_RATE_GROUP_START + i), uint256(writeOffGroups[i].percentage)));
        }
        return sum;
    }

    /// @notice calculates and returns the current NAV and updates the state
    /// @return nav_ current NAV
    function calcUpdateNAV() public returns (uint256 nav_) {
        (uint256 totalDiscount, uint256 overdue, uint256 writeOffs) = currentPVs();

        overdueLoans = overdue;
        latestDiscount = totalDiscount;

        latestNAV = safeAdd(safeAdd(totalDiscount, overdue), writeOffs);
        lastNAVUpdate = uniqueDayTimestamp(block.timestamp);
        return latestNAV;
    }

    /// @notice re-calculates the nav in a non-optimized way
    ///  the method is not updating the NAV to latest block.timestamp
    /// @return nav_ current NAV
    function reCalcNAV() public returns (uint256 nav_) {
        uint256 latestDiscount_ = reCalcTotalDiscount();

        latestNAV = safeAdd(latestDiscount_, safeSub(latestNAV, latestDiscount));
        latestDiscount = latestDiscount_;
        return latestNAV;
    }

    /// @notice re-calculates the totalDiscount in a non-optimized way based on lastNAVUpdate
    /// @return latestDiscount_ returns the total discount of the active loans
    function reCalcTotalDiscount() public view returns (uint256 latestDiscount_) {
        latestDiscount_ = 0;

        for (uint256 loanID = 1; loanID < loanCount; loanID++) {
            bytes32 nftID_ = nftID(loanID);
            uint256 maturityDate_ = maturityDate(nftID_);

            if (maturityDate_ < lastNAVUpdate) {
                continue;
            }

            latestDiscount_ =
                            safeAdd(latestDiscount_, calcDiscount(discountRate, futureValue(nftID_), lastNAVUpdate, maturityDate_));
        }
        return latestDiscount_;
    }

    /// @notice update the value (apprasial) of the collateral NFT
    function update(bytes32 nftID_, uint256 value) public auth {
        // switch of collateral risk group results in new: ceiling, threshold for existing loan
        details[nftID_].nftValues = toUint128(value);
    }

    /// @notice updates the risk group of active loans (borrowed and unborrowed loans)
    /// @param nftID_ the nftID of the loan
    /// @param risk_ the new value appraisal of the collateral NFT
    /// @param risk_ the new risk group
    function update(bytes32 nftID_, uint256 value, uint256 risk_) public auth {
        uint256 nnow = uniqueDayTimestamp(block.timestamp);
        details[nftID_].nftValues = toUint128(value);

        // no change in risk group
        if (risk_ == risk(nftID_)) {
            return;
        }

        details[nftID_].risk = toUint128(risk_);

        // update nav -> latestNAVUpdate = now
        if (nnow > lastNAVUpdate) {
            calcUpdateNAV();
        }

        // switch of collateral risk group results in new: ceiling, threshold and interest rate for existing loan
        // change to new rate interestRate immediately in pile if loan debt exists
        uint256 loan = uint256(nftID_);
        if (pie[loan] != 0) {
            changeRate(loan, risk_);
        }

        // no currencyAmount borrowed yet
        if (futureValue(nftID_) == 0) {
            return;
        }

        uint256 maturityDate_ = maturityDate(nftID_);

        // Changing the risk group of an nft, might lead to a new interest rate for the dependant loan.
        // New interest rate leads to a future value.
        // recalculation required
        uint256 fvDecrease = futureValue(nftID_);
        uint256 navDecrease = calcDiscount(discountRate, fvDecrease, nnow, maturityDate_);
        buckets[maturityDate_] = safeSub(buckets[maturityDate_], fvDecrease);
        latestDiscount = safeSub(latestDiscount, navDecrease);
        latestNAV = safeSub(latestNAV, navDecrease);

        // update latest NAV
        // update latest Discount
        Rate memory _rate = rates[loanRates[loan]];
        ILoanRegistry.LoanEntry memory loanEntry = registry.getLoanRegistry().getEntry(bytes32(loan));
        details[nftID_].futureValue = toUint128(
            calcFutureValue(_rate.ratePerSecond, debt(loan), maturityDate(nftID_), recoveryRatePD(loanEntry.riskScore, loanEntry.expirationTimestamp - loanEntry.issuanceBlockTimestamp))
        );

        uint256 fvIncrease = futureValue(nftID_);
        uint256 navIncrease = calcDiscount(discountRate, fvIncrease, nnow, maturityDate_);
        buckets[maturityDate_] = safeAdd(buckets[maturityDate_], fvIncrease);
        latestDiscount = safeAdd(latestDiscount, navIncrease);
        latestNAV = safeAdd(latestNAV, navIncrease);
    }

    /// @notice returns the nftID for the underlying collateral nft
    /// @param loan the loan id
    /// @return nftID_ the nftID of the loan
    function nftID(uint256 loan) public pure returns (bytes32 nftID_) {
        return bytes32(loan);
    }

    /// @notice returns true if the present value of a loan is zero
    /// true if all debt is repaid or debt is 100% written-off
    /// @param loan the loan id
    /// @return isZeroPV true if the present value of a loan is zero
    function zeroPV(uint256 loan) public view returns (bool isZeroPV) {
        if (debt(loan) == 0) {
            return true;
        }

        uint256 rate = loanRates[loan];

        if (rate < WRITEOFF_RATE_GROUP_START) {
            return false;
        }

        return writeOffGroups[safeSub(rate, WRITEOFF_RATE_GROUP_START)].percentage == 0;
    }

    /// @notice returns the current valid write off group of a loan
    /// @param loan the loan id
    /// @return writeOffGroup_ the current valid write off group of a loan
    function currentValidWriteOffGroup(uint256 loan) public view returns (uint256 writeOffGroup_) {
        bytes32 nftID_ = nftID(loan);
        uint256 maturityDate_ = maturityDate(nftID_);
        uint256 nnow = uniqueDayTimestamp(block.timestamp);
        ILoanRegistry.LoanEntry memory loanEntry = registry.getLoanRegistry().getEntry(nftID_);
        uint8 _loanRiskIndex = loanEntry.riskScore - 1;

        uint128 lastValidWriteOff = type(uint128).max;
        uint128 highestOverdueDays = 0;
        // it is not guaranteed that writeOff groups are sorted by overdue days
        for (uint128 i = 0; i < writeOffGroups.length; i++) {
            uint128 overdueDays = writeOffGroups[i].overdueDays;
            if (writeOffGroups[i].riskIndex == _loanRiskIndex && overdueDays >= highestOverdueDays && nnow >= maturityDate_ + overdueDays * 1 days) {
                lastValidWriteOff = i;
                highestOverdueDays = overdueDays;
            }
        }

        // returns type(uint128).max if no write-off group is valid for this loan
        return lastValidWriteOff;
    }

    function incDebt(uint256 loan, uint256 currencyAmount) public auth {
        uint256 rate = loanRates[loan];
        require(block.timestamp == rates[rate].lastUpdated, "rate-group-not-updated");
        uint256 pieAmount = toPie(rates[rate].chi, currencyAmount);

        pie[loan] = safeAdd(pie[loan], pieAmount);
        rates[rate].pie = safeAdd(rates[rate].pie, pieAmount);

        emit IncreaseDebt(loan, currencyAmount);
    }

    function decDebt(uint256 loan, uint256 currencyAmount) private {
        uint256 rate = loanRates[loan];
        require(block.timestamp == rates[rate].lastUpdated, "rate-group-not-updated");
        uint256 pieAmount = toPie(rates[rate].chi, currencyAmount);

        pie[loan] = safeSub(pie[loan], pieAmount);
        rates[rate].pie = safeSub(rates[rate].pie, pieAmount);

        emit DecreaseDebt(loan, currencyAmount);
    }

    function debt(uint256 loan) public view returns (uint256 loanDebt) {
        uint256 rate_ = loanRates[loan];
        uint256 chi_ = rates[rate_].chi;
        if (block.timestamp >= rates[rate_].lastUpdated) {
            chi_ = chargeInterest(rates[rate_].chi, rates[rate_].ratePerSecond, rates[rate_].lastUpdated);
        }
        return toAmount(chi_, pie[loan]);
    }

    function rateDebt(uint256 rate) public view returns (uint256 totalDebt) {
        uint256 chi_ = rates[rate].chi;
        uint256 pie_ = rates[rate].pie;

        if (block.timestamp >= rates[rate].lastUpdated) {
            chi_ = chargeInterest(rates[rate].chi, rates[rate].ratePerSecond, rates[rate].lastUpdated);
        }
        return toAmount(chi_, pie_);
    }

    function setRate(uint256 loan, uint256 rate) public auth {
        require(pie[loan] == 0, "non-zero-debt");
        // rate category has to be initiated
        require(rates[rate].chi != 0, "rate-group-not-set");
        loanRates[loan] = rate;
        emit SetRate(loan, rate);
    }

    function changeRate(uint256 loan, uint256 newRate) internal {
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

    function accrue(uint256 loan) public {
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

    /// Interest functions
    // @notice This function provides compounding in seconds
    // @param chi Accumulated interest rate over time
    // @param ratePerSecond Interest rate accumulation per second in RAD(10ˆ27)
    // @param lastUpdated When the interest rate was last updated
    // @param pie Total sum of all amounts accumulating under one interest rate, divided by that rate
    // @return The new accumulated rate, as well as the difference between the debt calculated with the old and new accumulated rates.
    function compounding(uint chi, uint ratePerSecond, uint lastUpdated, uint pie) public view returns (uint, uint) {
        require(block.timestamp >= lastUpdated, "tinlake-math/invalid-timestamp");
        require(chi != 0);
        // instead of a interestBearingAmount we use a accumulated interest rate index (chi)
        uint updatedChi = _chargeInterest(chi ,ratePerSecond, lastUpdated, block.timestamp);
        return (updatedChi, safeSub(rmul(updatedChi, pie), rmul(chi, pie)));
    }

    // @notice This function charge interest on a interestBearingAmount
    // @param interestBearingAmount is the interest bearing amount
    // @param ratePerSecond Interest rate accumulation per second in RAD(10ˆ27)
    // @param lastUpdated last time the interest has been charged
    // @return interestBearingAmount + interest
    function chargeInterest(uint interestBearingAmount, uint ratePerSecond, uint lastUpdated) public view returns (uint) {
        if (block.timestamp >= lastUpdated) {
            interestBearingAmount = _chargeInterest(interestBearingAmount, ratePerSecond, lastUpdated, block.timestamp);
        }
        return interestBearingAmount;
    }

    function _chargeInterest(uint interestBearingAmount, uint ratePerSecond, uint lastUpdated, uint current) internal pure returns (uint) {
        return rmul(rpow(ratePerSecond, current - lastUpdated, ONE), interestBearingAmount);
    }


    // convert pie to debt/savings amount
    function toAmount(uint chi, uint pie) public pure returns (uint) {
        return rmul(pie, chi);
    }

    // convert debt/savings amount to pie
    function toPie(uint chi, uint amount) public pure returns (uint) {
        return rdivup(amount, chi);
    }
}
