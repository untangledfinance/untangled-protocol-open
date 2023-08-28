// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

contract SignaturesLib {

    bytes constant internal PREFIX = "\x19Ethereum Signed Message:\n32";

    struct ECDSASignature {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    function isValidSignature(
        address signer,
        bytes32 hash,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
    public
    pure
    returns (bool valid)
    {
        bytes32 prefixedHash = keccak256(abi.encodePacked(PREFIX, hash));
        return ecrecover(prefixedHash, v, r, s) == signer;
    }
}
