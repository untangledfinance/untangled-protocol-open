pragma solidity ^0.8.0;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import "../base/UntangledBase.sol";
import "./Registry.sol";

/**
 * The ERC20TokenRegistry is a basic registry mapping token symbols
 * to their known, deployed addresses on the current blockchain.
 *
 * Note that the ERC20TokenRegistry does *not* mediate any of the
 * core protocol's business logic, but, rather, is a helpful
 * utility for Terms Contracts to use in encoding, decoding, and
 * resolving the addresses of currently deployed tokens.
 *
 * At this point in time, administration of the Token Registry is
 * under Untangled Techs' control.
 */
contract ERC20TokenRegistry is OwnableUpgradeable {
    mapping(uint256 => TokenAttributes) public indexToTokenAttributes;
    mapping(bytes32 => uint256) identifyHashToIndex;
    mapping(bytes32 => bool) isExistingTokens;

    uint256 public lastTokenIndex;

    struct TokenAttributes {
        string symbol;
        string issuer;
        // The name of the given token, e.g. "Canonical Wrapped Ether"
        string name;
        // The ERC20 contract address.
        address tokenAddress;
        // The number of digits that come after the decimal place when displaying token value.
        uint8 numDecimals;
    }

    Registry public registry;

    function initialize(Registry _registry) public initializer {
        __Ownable_init();
        registry = _registry;
    }


    //=------------------------------
    // INTERNAL FUNCS
    //=------------------------------
    function _isExistingToken(bytes32 indentifyHash) internal view returns (bool) {
        return isExistingTokens[indentifyHash];
    }

    /**
     * Prerequisite: only if this is existing token
     */
    function _getTokenIndex(string memory _symbol, string memory _issuer) internal view returns (uint256) {
        bytes32 indentifyHash = keccak256(abi.encodePacked(_symbol, _issuer));
        return identifyHashToIndex[indentifyHash];
    }

    function _getTokenIndex(bytes32 _indentifyHash) internal view returns (uint256) {
        return identifyHashToIndex[_indentifyHash];
    }

    //=------------------------------
    // EXTERNAL FUNCS
    //=------------------------------

    //====== EX:SEND ======
    /**
     * Maps the given symbol to the given token attributes.
     */
    function setTokenAttributes(
        string memory _symbol,
        string memory _issuer,
        string memory _tokenName,
        address _tokenAddress,
        uint8 _numDecimals
    ) public onlyOwner {
        bytes32 identifyHash = keccak256(abi.encodePacked(_symbol, _issuer));
        TokenAttributes memory attributes;
        // If this is existing token, need to override
        if (_isExistingToken(identifyHash)) {
            // Attempt to retrieve the token's attributes from the registry.
            uint256 index = _getTokenIndex(identifyHash);
            attributes = indexToTokenAttributes[index];

            attributes.symbol = _symbol;
            attributes.issuer = _issuer;
            attributes.tokenAddress = _tokenAddress;
            attributes.numDecimals = _numDecimals;
            attributes.name = _tokenName;

            indexToTokenAttributes[index] = attributes;
        } else {
            attributes = TokenAttributes({
                symbol: _symbol,
                issuer: _issuer,
                tokenAddress: _tokenAddress,
                numDecimals: _numDecimals,
                name: _tokenName
            });
            identifyHashToIndex[identifyHash] = lastTokenIndex;
            isExistingTokens[identifyHash] = true;
            indexToTokenAttributes[lastTokenIndex] = attributes;
            lastTokenIndex++;
        }
        // Update this contract's storage.
    }

    //====== EX:CALL ======
    /**
     * Given a symbol, resolves the current address of the token the symbol is mapped to.
     */
    function getTokenAddress(string memory _symbol, string memory _issuer) public view returns (address) {
        bytes32 identifyHash = keccak256(abi.encodePacked(_symbol, _issuer));
        return indexToTokenAttributes[_getTokenIndex(identifyHash)].tokenAddress;
    }

    function getTokenIndex(string memory _symbol, string memory _issuer) public view returns (uint256) {
        return _getTokenIndex(_symbol, _issuer);
    }

    function getTokenAddressByIndex(uint256 _index) public view returns (address) {
        return indexToTokenAttributes[_index].tokenAddress;
    }

    /**
     * Given an index, resolves the symbol of the token at that index in the registry's
     * token symbol list.
     */
    function getTokenSymbolByIndex(uint256 _index) public view returns (string memory) {
        return indexToTokenAttributes[_index].symbol;
    }

    /**
     * Given the index for a token in the registry, returns the number of decimals as provided in
     * the associated TokensAttribute struct.
     *
     * Example:
     *   getNumDecimalsByIndex(1);
     *   => 18
     */
    function getNumDecimalsByIndex(uint256 _index) public view returns (uint8) {
        return indexToTokenAttributes[_index].numDecimals;
    }

    /**
     * Given the index for a token in the registry, returns the name of the token as provided in
     * the associated TokensAttribute struct.
     *
     * Example:
     *   getTokenNameByIndex(1);
     *   => "Canonical Wrapped Ether"
     */
    function getTokenNameByIndex(uint256 _index) public view returns (string memory) {
        return indexToTokenAttributes[_index].name;
    }

    /**
     * Given the symbol for a token in the registry, returns a tuple containing the token's address,
     * the token's index in the registry, the token's name, and the number of decimals.
     *
     * Example:
     *   getTokenAttributesBySymbol("WETH");
     *   => ["0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2", 1, "Canonical Wrapped Ether", 18]
     */
    function getTokenAttributes(string memory _symbol, string memory _issuer)
        public
        view
        returns (
            string memory,
            string memory,
            string memory,
            address,
            uint8
        )
    {
        bytes32 identifyHash = keccak256(abi.encodePacked(_symbol, _issuer));

        TokenAttributes storage attributes = indexToTokenAttributes[_getTokenIndex(identifyHash)];

        return (attributes.symbol, attributes.issuer, attributes.name, attributes.tokenAddress, attributes.numDecimals);
    }

    /**
     * Given the index for a token in the registry, returns a tuple containing the token's address,
     * the token's symbol, the token's name, and the number of decimals.
     *
     * Example:
     *   getTokenAttributesByIndex(1);
     *   => ["0xc02aaa39b223fkfkamakaakdfierjfdnvanfaf", "WETH", "Canonical Wrapped Ether", 18]
     */
    function getTokenAttributesByIndex(uint256 _index)
        public
        view
        returns (
            string memory,
            string memory,
            string memory,
            address,
            uint8
        )
    {
        TokenAttributes storage attributes = indexToTokenAttributes[_index];

        return (attributes.symbol, attributes.issuer, attributes.name, attributes.tokenAddress, attributes.numDecimals);
    }
}
