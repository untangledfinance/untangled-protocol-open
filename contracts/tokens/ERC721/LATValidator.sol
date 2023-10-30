// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/cryptography/SignatureCheckerUpgradeable.sol';
import {UntangledMath} from '../../libraries/UntangledMath.sol';
import './IERC5008.sol';
import './types.sol';

contract LATValidator is IERC5008, EIP712Upgradeable {
    using SignatureCheckerUpgradeable for address;
    using ECDSAUpgradeable for bytes32;

    bytes32 internal constant LAT_TYPEHASH =
        keccak256('LoanAssetToken(uint256[] tokenIds,uint256[] nonces,address validator)');

    mapping(uint256 => uint256) internal _nonces;

    modifier requireValidator(LoanAssetInfo calldata info) {
        require(_checkValidator(info), 'LATValidator: invalid validator signature');
        _;
    }

    modifier requireNonceValid(LoanAssetInfo calldata info) {
        _checkNonceValid(info);
        _;
    }

    function _checkNonceValid(LoanAssetInfo calldata info) internal {
        for (uint256 i = 0; i < info.tokenIds.length; i = UntangledMath.uncheckedInc(i)) {
            require(_nonces[info.tokenIds[i]] == info.nonces[i], 'LATValidator: invalid nonce');
            unchecked {
                _nonces[info.tokenIds[i]] = _nonces[info.tokenIds[i]] + 1;
            }

            emit NonceChanged(info.tokenIds[i], _nonces[info.tokenIds[i]]);
        }
    }

    function __LATValidator_init() internal onlyInitializing {
        __EIP712_init_unchained('UntangledLoanAssetToken', '0.0.1');
        __LATValidator_init_unchained();
    }

    function __LATValidator_init_unchained() internal onlyInitializing {}

    function nonce(uint256 tokenId) external view override returns (uint256) {
        return _nonces[tokenId];
    }

    function _checkValidator(LoanAssetInfo calldata latInfo) internal view returns (bool) {
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    LAT_TYPEHASH,
                    keccak256(abi.encodePacked(latInfo.tokenIds)),
                    keccak256(abi.encodePacked(latInfo.nonces)),
                    latInfo.validator
                )
            )
        );

        return latInfo.validator.isValidSignatureNow(digest, latInfo.validateSignature);
    }

    function domainSeparatorV4() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    uint256[50] private __gap;
}
