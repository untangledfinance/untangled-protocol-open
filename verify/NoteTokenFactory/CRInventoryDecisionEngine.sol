// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./SignaturesLib.sol";

contract CRInventoryDecisionEngine is SignaturesLib {
    using SafeMath for uint;

    uint public constant PRICE_PRECISION = 4; //Number decimals for price of collateral token
    uint public constant CR_PRECISION = 2; //Number decimals for collateral ratio

    uint public constant MAX_PRICE_TTL_IN_SECONDS = 300;

    // These values must be dynamic in future, query from token information in registry
    uint public COLLATERAL_PRECISION = 3; // Number decimals of CMA token
    uint public PRINCIPAL_PRECISION = 2; // Number decimals of FAT

    uint256 constant MAX_UINT256 = ~uint256(0);

    //==============================
    // Internal funcs
    //==============================
    function _computeCR(
        uint _collateralAmount,
        uint _price,
        uint _invoiceAmount,
        uint _principalAmount
    )
        internal view returns (uint)
    {
        if (_principalAmount == 0) {
            return MAX_UINT256;
        }
        uint collateralValue = (_price.mul(_collateralAmount) + _invoiceAmount.mul(10 ** (PRICE_PRECISION - PRINCIPAL_PRECISION)).mul(10 ** COLLATERAL_PRECISION))
                                    .mul(10 ** PRINCIPAL_PRECISION).mul(10 ** CR_PRECISION).mul(10 ** 2);
        uint principalValue = _principalAmount.mul(10 ** COLLATERAL_PRECISION).mul(10 ** PRICE_PRECISION);
        return collateralValue.div(principalValue);
    }

    function _computeCR(uint _collateralAmount, uint _principalAmount) internal view returns (uint) {
        uint collateralValue = _collateralAmount.mul(10 ** PRINCIPAL_PRECISION).mul(10 ** CR_PRECISION).mul(10 ** 2);
        return collateralValue.div(_principalAmount);
    }

    // Compute commodity value in principal decimals number
    function _computePriceValue(
        uint _collateralAmount,
        uint _price
    ) internal view returns (uint) {
        return _price.mul(_collateralAmount).div(10 ** (PRICE_PRECISION - PRINCIPAL_PRECISION + COLLATERAL_PRECISION));
    }

    // Compute require principal value to satisfy min collateral ratio
    function _computePrincipalValueRequire(
        uint _collateralAmount,
        uint _price,
        uint256 invoiceValue,
        uint256 minCollateralRatio
    ) internal view returns (uint) {
        return _price.mul(_collateralAmount).mul(10 ** CR_PRECISION).mul(10 ** 2).div(10 ** (PRICE_PRECISION - PRINCIPAL_PRECISION + COLLATERAL_PRECISION))
            .div(minCollateralRatio) + invoiceValue.mul(10 ** CR_PRECISION).mul( 10 ** 2).div(minCollateralRatio);
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
