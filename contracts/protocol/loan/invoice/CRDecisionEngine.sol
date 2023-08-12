// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../../../libraries/SignaturesLib.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract CRDecisionEngine is SignaturesLib {
    using SafeMath for uint;

    // Maximum 4 decmal places for the price of collteral token
    uint public constant PRICE_PRECISION = 4;
    uint public constant CR_PRECISION = 2;

    uint public constant MAX_PRICE_TTL_IN_SECONDS = 300;

    // These values must be dynamic in future, query from token information in registry
    uint public COLLATERAL_PRECISION = 3; // Number decimals of CAT token
    uint public PRINCIPAL_PRECISION = 2; // Number decimaals of FAT

    uint256 constant MAX_UINT256 = ~uint256(0);

    //==============================
    // Internal funcs
    //==============================
    function _computeCR(
        uint _collateralAmount,
        uint _price,
        uint _principalAmount
    )
        internal view returns (uint)
    {
        if (_principalAmount == 0) {
            return MAX_UINT256;
        }

        uint collateralValue = _price.mul(_collateralAmount).mul(10 ** PRINCIPAL_PRECISION).mul(10 ** CR_PRECISION).mul(10 ** 2);
        uint principalValue = _principalAmount.mul(10 ** COLLATERAL_PRECISION).mul(10 ** PRICE_PRECISION);
        return collateralValue.div(principalValue);
    }

    function _computeInvoiceCR(uint _collateralAmount, uint _principalAmount) internal view returns (uint) {
        if (_principalAmount == 0) {
            return MAX_UINT256;
        }

        uint collateralValue = _collateralAmount.mul(10 ** PRINCIPAL_PRECISION).mul(10 ** CR_PRECISION).mul(10 ** 2);
        return collateralValue.div(_principalAmount.mul(10 ** PRINCIPAL_PRECISION));
    }

    /**
    * @dev TODO: Verify Operator's signature here
    */
    function _verifyPrice(uint _timestamp) internal view returns(bool) {
        uint minPriceTimestamp = uint(block.timestamp).sub(MAX_PRICE_TTL_IN_SECONDS);
        if (_timestamp < minPriceTimestamp) {
            return false;
        }
        return true;
    }
}
