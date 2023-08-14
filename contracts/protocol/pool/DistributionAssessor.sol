// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import './base/Interest.sol';

import './base/SecuritizationPoolServiceBase.sol';
import '../../interfaces/INoteToken.sol';

contract DistributionAssessor is Interest, SecuritizationPoolServiceBase, IDistributionAssessor {
    using ConfigHelper for Registry;

    // get current individual asset for SOT tranche
    function getSOTTokenPrice(address pool) public view override returns (uint256) {
        if (pool == address(0)) return 0;
        ISecuritizationPool securitizationPool = ISecuritizationPool(pool);

        ERC20 noteToken = ERC20(securitizationPool.sotToken());
        uint256 seniorSupply = noteToken.totalSupply();
        uint256 seniorDecimals = noteToken.decimals();

        if (address(noteToken) == address(0) || noteToken.totalSupply() == 0) return 0;
        ISecuritizationPoolValueService poolService = registry.getSecuritizationPoolValueService();
        uint256 seniorAsset = poolService.getSeniorAsset(pool);
        return ((seniorAsset) * (10**seniorDecimals)) / seniorSupply;
    }

    // get current individual asset for SOT tranche
    function calcAssetValue(
        address pool,
        address tokenAddress,
        address investor
    ) external view override returns (uint256 principal, uint256 interest) {
        ISecuritizationPool securitizationPool = ISecuritizationPool(pool);

        address sotToken = securitizationPool.sotToken();
        address jotToken = securitizationPool.jotToken();

        require(tokenAddress == sotToken || tokenAddress == jotToken, 'DistributionAssessor: unknown-tranche-address');

        uint256 openingBlockTimestamp = securitizationPool.openingBlockTimestamp();

        if (tokenAddress == sotToken) {
            uint32 interestRateSOT = securitizationPool.interestRateSOT();
            uint256 currentPrincipal = IERC20(tokenAddress).balanceOf(investor);
            uint256 tokenRedeem = securitizationPool.lockedRedeemBalances(sotToken, investor);
            return
                _calcSeniorAssetValue(
                    currentPrincipal - tokenRedeem,
                    interestRateSOT,
                    openingBlockTimestamp,
                    block.timestamp
                );
        } else {
            return _calcPrincipalInterestJOT(pool, jotToken, investor);
        }
    }

    function calcCorrespondingTotalAssetValue(
        address tokenAddress,
        address investor,
        uint256 endTime
    ) external view override returns (uint256) {
        (uint256 principal, uint256 interest) = _calcCorrespondingAssetValue(tokenAddress, investor, endTime);
        return principal + interest;
    }

    function calcCorrespondingAssetValue(
        address tokenAddress,
        address investor,
        uint256 endTime
    ) external view returns (uint256 principal, uint256 interest) {
        return _calcCorrespondingAssetValue(tokenAddress, investor, endTime);
    }

    function _calcCorrespondingAssetValue(
        address tokenAddress,
        address investor,
        uint256 endTime
    ) internal view returns (uint256 principal, uint256 interest) {
        INoteToken notesToken = INoteToken(tokenAddress);
        ISecuritizationPool securitizationPool = ISecuritizationPool(notesToken.poolAddress());

        if (Configuration.NOTE_TOKEN_TYPE(notesToken.noteTokenType()) == Configuration.NOTE_TOKEN_TYPE.SENIOR) {
            uint256 openingBlockTimestamp = securitizationPool.openingBlockTimestamp();
            uint32 interestRateSOT = securitizationPool.interestRateSOT();
            return
                _calcPrincipalInterestSOT(
                    securitizationPool,
                    tokenAddress,
                    investor,
                    interestRateSOT,
                    openingBlockTimestamp,
                    endTime
                );
        } else {
            return _calcPrincipalInterestJOT(notesToken.poolAddress(), tokenAddress, investor);
        }
    }

    function calcAssetValue(
        address pool,
        address tokenAddress,
        address[] calldata investors
    ) external view returns (uint256[] memory principals, uint256[] memory interests) {
        uint256 investorsLength = investors.length;
        principals = new uint256[](investorsLength);
        interests = new uint256[](investorsLength);

        ISecuritizationPool securitizationPool = ISecuritizationPool(pool);

        address sotToken = securitizationPool.sotToken();
        address jotToken = securitizationPool.jotToken();
        require(tokenAddress == sotToken || tokenAddress == jotToken, 'DistributionAssessor: unknown-tranche-address');

        uint256 openingBlockTimestamp = securitizationPool.openingBlockTimestamp();
        
        if (tokenAddress == sotToken) {
            uint32 interestRateSOT = securitizationPool.interestRateSOT();
            
            for (uint256 i = 0; i < investorsLength; i++) {
                (uint256 principal, uint256 interest) = _calcPrincipalInterestSOT(
                    securitizationPool,
                    sotToken,
                    investors[i],
                    interestRateSOT,
                    openingBlockTimestamp,
                    block.timestamp
                );

                principals[i] = principal;
                interests[i] = interest;
            }
        } else {
            for (uint256 i = 0; i <investorsLength; i++) {
                (uint256 principal, uint256 interest) = _calcPrincipalInterestJOT(
                    pool,
                    jotToken,
                    investors[i]
                    
                );
                principals[i] = principal;
                interests[i] = interest;
            }
        }
    }

    function calcCorrespondingAssetValue(
        address tokenAddress,
        address[] calldata investors,
        uint256 endTime
    ) external view returns (uint256[] memory principals, uint256[] memory interests) {
         uint256 investorsLength = investors.length;
        principals = new uint256[](investorsLength);
        interests = new uint256[](investorsLength);

        for (uint256 i = 0; i < investorsLength; i++) {
            (principals[i], interests[i]) = _calcCorrespondingAssetValue(tokenAddress, investors[i], endTime);
        }
    }

    function calcTokenPrice(address pool, address tokenAddress) external view override returns (uint256) {
        ISecuritizationPool securitizationPool = ISecuritizationPool(pool);
        if (tokenAddress == securitizationPool.sotToken())
            return getSOTTokenPrice(address(securitizationPool));
        else if (tokenAddress == securitizationPool.jotToken())
            return getJOTTokenPrice(securitizationPool);
        return 0;
    }

    function getJOTTokenPrice(
        ISecuritizationPool securitizationPool
        
    ) public view override returns (uint256) {
        if (address(securitizationPool) == address(0)) {
            return 0;
        }
        // require(address(securitizationPool) != address(0), 'pool was not deployed');
        // ISecuritizationPool securitizationPool = ISecuritizationPool(pool);
        address tokenAddress = securitizationPool.jotToken();
        uint256 tokenSupply = INoteToken(tokenAddress).totalSupply();
        uint256 tokenDecimals = INoteToken(tokenAddress).decimals();
        if (tokenAddress == address(0) || tokenSupply == 0) {
            return 0;
        }
        // address pool = address(securitizationPool);
        ISecuritizationPoolValueService poolService = registry.getSecuritizationPoolValueService();
        uint256 juniorAsset = poolService.getJuniorAsset(address(securitizationPool));
        return (juniorAsset * (10**tokenDecimals)) / tokenSupply;
    }

    function calcSeniorAssetValue(address pool) public view returns (address, uint256) {
        ISecuritizationPool securitizationPool = ISecuritizationPool(pool);
        INoteToken sot = INoteToken(securitizationPool.sotToken());

        uint256 price = getSOTTokenPrice(address(securitizationPool));
        uint256 totalSotSupply = sot.totalSupply();
        uint256 ONE_SOT = 10 ** uint256(sot.decimals());

        return (address(sot), (price * totalSotSupply) / ONE_SOT);
    }

    function getCashBalance(address pool) public view override returns (uint256) {
        ISecuritizationPool securitizationPool = ISecuritizationPool(pool);
        return
            IERC20(securitizationPool.underlyingCurrency()).balanceOf(securitizationPool.pot()) -
            securitizationPool.totalLockedDistributeBalance();
    }

    function _calcJuniorAssetValue(address pool, uint256 timestamp) internal view returns (uint256) {
        (, uint256 seniorAssetValue) = calcSeniorAssetValue(pool);

        uint256 available = registry.getSecuritizationPoolValueService().getExpectedAssetsValue(pool, timestamp) +
            this.getCashBalance(pool);

        // senior debt needs to be covered first
        if (available > seniorAssetValue) {
            return available - seniorAssetValue;
        }
        // currently junior would receive nothing
        return 0;
    }

    function _calcPrincipalInterestSOT(
        ISecuritizationPool securitizationPool,
        address sotToken,
        address investor,
        uint32 interestRateSOT,
        uint256 openingBlockTimestamp,
        uint256 timestamp
    ) internal view returns (uint256 principal, uint256 interest) {
        uint256 tokenRedeem = securitizationPool.lockedRedeemBalances(sotToken, investor);

        return
            _calcSeniorAssetValue(
                IERC20(sotToken).balanceOf(investor) - tokenRedeem,
                interestRateSOT,
                openingBlockTimestamp,
                timestamp
            );
    }

    function _calcPrincipalInterestJOT(
        address pool,
        address jotToken,
        address investor
      
    ) internal view returns (uint256 principal, uint256 interest) {
        uint256 tokenPrice = getJOTTokenPrice(ISecuritizationPool(pool));
        uint256 currentPrincipal = IERC20(jotToken).balanceOf(investor);
        if (tokenPrice > Configuration.PRICE_SCALING_FACTOR)
            return (
                currentPrincipal,
                (currentPrincipal * tokenPrice) / Configuration.PRICE_SCALING_FACTOR - currentPrincipal
            );
        else return ((currentPrincipal * tokenPrice) / Configuration.PRICE_SCALING_FACTOR, 0);
    }

    function _getPrincipalLeftOfSOT(
        ISecuritizationPool securitizationPool,
        address sotToken
    ) internal view returns (uint256) {
        uint256 totalPrincipal = 0;
        uint256 totalTokenRedeem = 0;
        if (sotToken != address(0x0)) {
            totalPrincipal = IERC20(sotToken).totalSupply();
            totalTokenRedeem = securitizationPool.totalLockedRedeemBalances(sotToken);
        }

        return totalPrincipal - totalTokenRedeem;
    }

    function _calcSeniorAssetValue(
        uint256 _currentPrincipalAmount,
        uint256 _annualInterestRate,
        uint256 _startTermTimestamp,
        uint256 _timestamp
    ) internal pure returns (uint256 principal, uint256 interest) {
        principal = _currentPrincipalAmount;
        interest = chargeLendingInterest(_currentPrincipalAmount, _annualInterestRate, _startTermTimestamp, _timestamp);
    }
}
