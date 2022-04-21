pragma solidity ^0.8.0;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import "../storage/Registry.sol";

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
abstract contract IERC20TokenRegistry is OwnableUpgradeable {
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

    function initialize(Registry _registry) public virtual;

    //=------------------------------
    // EXTERNAL FUNCS
    //=------------------------------

    //====== EX:SEND ======
    /**
     * Maps the given symbol to the given token attributes.
     */
    function setTokenAttributes(string memory _symbol, string memory _issuer, string memory _tokenName, address _tokenAddress, uint8 _numDecimals ) public virtual;

    //====== EX:CALL ======
    /**
     * Given a symbol, resolves the current address of the token the symbol is mapped to.
     */
    function getTokenAddress(string memory _symbol, string memory _issuer) public virtual view returns (address);

    function getTokenIndex(string memory _symbol, string memory _issuer) public virtual view returns (uint256);

    function getTokenAddressByIndex(uint256 _index) public virtual view returns (address);

    /**
     * Given an index, resolves the symbol of the token at that index in the registry's
     * token symbol list.
     */
    function getTokenSymbolByIndex(uint256 _index) public virtual view returns (string memory);

    /**
     * Given the index for a token in the registry, returns the number of decimals as provided in
     * the associated TokensAttribute struct.
     *
     * Example:
     *   getNumDecimalsByIndex(1);
     *   => 18
     */
    function getNumDecimalsByIndex(uint256 _index) public virtual view returns (uint8);

    /**
     * Given the index for a token in the registry, returns the name of the token as provided in
     * the associated TokensAttribute struct.
     *
     * Example:
     *   getTokenNameByIndex(1);
     *   => "Canonical Wrapped Ether"
     */
    function getTokenNameByIndex(uint256 _index) public virtual view returns (string memory);

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
        virtual
        view
        returns (
            string memory,
            string memory,
            string memory,
            address,
            uint8
        );
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
        virtual
        view
        returns (
            string memory,
            string memory,
            string memory,
            address,
            uint8
        );
}
