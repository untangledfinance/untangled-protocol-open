// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol';
import './IERC5008.sol';
import './types.sol';

contract LATValidator is IERC5008, EIP712Upgradeable {
    bytes32 internal constant LAT_TYPEHASH =
        keccak256('LoanAssetInfo(uint256 tokenId,uint256 nonce,address validator)');

    mapping(uint256 => uint256) internal _nonces;

    modifier requireValidator(LoanAssetInfo calldata info) {
        require(_checkValidator(info), 'LATValidator: invalid validator signature');
        _;
    }

    function __LATValidator_init() internal onlyInitializing {
        __EIP712_init_unchained("UntangledLoanAssetToken", "0.0.1");
        __LATValidator_init_unchained();
    }

    function __LATValidator_init_unchained() internal onlyInitializing {

    }

    function nonce(uint256 tokenId) external view override returns (uint256) {
        return _nonces[tokenId];
    }

    function _checkValidator(LoanAssetInfo calldata latInfo) internal view returns(bool) {
        // EIP check

        return true;
    }

    uint256[50] private __gap;
}
