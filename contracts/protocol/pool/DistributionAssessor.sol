// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import './base/Interest.sol';

import './base/SecuritizationPoolServiceBase.sol';
import '../../interfaces/INoteToken.sol';

contract DistributionAssessor is Interest, SecuritizationPoolServiceBase, IDistributionAssessor {
    using ConfigHelper for Registry;

    // get current individual asset for SOT tranche
    /// @inheritdoc IDistributionAssessor
    function getSOTTokenPrice(address pool) public view override returns (uint256) {
        require(pool != address(0), "DistributionAssessor: Invalid pool address");
        ISecuritizationPool securitizationPool = ISecuritizationPool(pool);

        ERC20 noteToken = ERC20(securitizationPool.sotToken());
        uint256 seniorSupply = noteToken.totalSupply();
        uint256 seniorDecimals = noteToken.decimals();

        require(address(noteToken) != address(0), "DistributionAssessor: Invalid note token address");
        // In initial state, SOT price = 1$
        if (noteToken.totalSupply() == 0) return 10 ** (ERC20(securitizationPool.underlyingCurrency()).decimals()-seniorDecimals);
        ISecuritizationPoolValueService poolService = registry.getSecuritizationPoolValueService();
        uint256 seniorAsset = poolService.getSeniorAsset(pool);
        return ((seniorAsset) * (10**seniorDecimals)) / seniorSupply;
    }

    /// @inheritdoc IDistributionAssessor
    function calcCorrespondingTotalAssetValue(
        address tokenAddress,
        address investor
    ) external view override returns (uint256) {
        return _calcCorrespondingAssetValue(tokenAddress, investor);
    }

    /// @notice Calculate SOT/JOT asset value belongs to an investor
    /// @param tokenAddress Address of SOT or JOT token
    /// @param investor Investor's wallet
    /// @return The value in pool's underlying currency
    function calcCorrespondingAssetValue(
        address tokenAddress,
        address investor
    ) external view returns (uint256) {
        return _calcCorrespondingAssetValue(tokenAddress, investor);
    }

    /// @dev Calculate SOT/JOT asset value belongs to an investor
    /// @param tokenAddress Address of SOT or JOT token
    /// @param investor Investor's wallet
    /// @return The value in pool's underlying currency
    function _calcCorrespondingAssetValue(
        address tokenAddress,
        address investor
    ) internal view returns (uint256) {
        INoteToken notesToken = INoteToken(tokenAddress);
        ISecuritizationPool securitizationPool = ISecuritizationPool(notesToken.poolAddress());

        if (Configuration.NOTE_TOKEN_TYPE(notesToken.noteTokenType()) == Configuration.NOTE_TOKEN_TYPE.SENIOR) {
            uint256 tokenRedeem = securitizationPool.lockedRedeemBalances(tokenAddress, investor);
            uint256 sotBalance = notesToken.balanceOf(investor) - tokenRedeem;
            uint256 sotPrice = getSOTTokenPrice(notesToken.poolAddress());
            return sotBalance*sotPrice;
        } else {
            uint256 tokenRedeem = securitizationPool.lockedRedeemBalances(tokenAddress, investor);
            uint256 jotBalance = notesToken.balanceOf(investor) - tokenRedeem;
            uint256 jotPrice = getJOTTokenPrice(securitizationPool);
            return jotBalance * jotPrice;
        }
    }

    /// @notice Calculate SOT/JOT asset value for multiple investors
    function calcCorrespondingAssetValue(
        address tokenAddress,
        address[] calldata investors
    ) external view returns (uint256[] memory values) {
         uint256 investorsLength = investors.length;
        values = new uint256[](investorsLength);

        for (uint256 i = 0; i < investorsLength; i++) {
            values[i] = _calcCorrespondingAssetValue(tokenAddress, investors[i]);
        }
    }

    /// @inheritdoc IDistributionAssessor
    function calcTokenPrice(address pool, address tokenAddress) external view override returns (uint256) {
        ISecuritizationPool securitizationPool = ISecuritizationPool(pool);
        if (tokenAddress == securitizationPool.sotToken())
            return getSOTTokenPrice(address(securitizationPool));
        else if (tokenAddress == securitizationPool.jotToken())
            return getJOTTokenPrice(securitizationPool);
        return 0;
    }

    /// @inheritdoc IDistributionAssessor
    function getJOTTokenPrice(
        ISecuritizationPool securitizationPool
    ) public view override returns (uint256) {
        require(address(securitizationPool) != address(0), "DistributionAssessor: Invalid pool address");
        // require(address(securitizationPool) != address(0), 'pool was not deployed');
        // ISecuritizationPool securitizationPool = ISecuritizationPool(pool);
        address tokenAddress = securitizationPool.jotToken();
        uint256 tokenSupply = INoteToken(tokenAddress).totalSupply();
        uint256 tokenDecimals = INoteToken(tokenAddress).decimals();
        require(tokenAddress != address(0), "DistributionAssessor: Invalid note token address");
        // In initial state, SOT price = 1$
        if (tokenSupply == 0) return 10**(ERC20(securitizationPool.underlyingCurrency()).decimals()-tokenDecimals);
        // address pool = address(securitizationPool);
        ISecuritizationPoolValueService poolService = registry.getSecuritizationPoolValueService();
        uint256 juniorAsset = poolService.getJuniorAsset(address(securitizationPool));
        return (juniorAsset * (10**tokenDecimals)) / tokenSupply;
    }

    /// @inheritdoc IDistributionAssessor
    function getCashBalance(address pool) public view override returns (uint256) {
        ISecuritizationPool securitizationPool = ISecuritizationPool(pool);
        return
            IERC20(securitizationPool.underlyingCurrency()).balanceOf(securitizationPool.pot()) -
            securitizationPool.totalLockedDistributeBalance();
    }

    /// @notice Calculate principal value and interest value for a JOT token
    /// @param pool Pool address which issues note token
    /// @param jotToken JOT token address
    /// @param investor Investor's wallet address
    /// @return principal A tuple contains JOT principal value and interest value
    /// @return interest A tuple contains JOT principal value and interest value
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

}
