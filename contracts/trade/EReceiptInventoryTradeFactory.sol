// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import './EReceiptInventoryTrade.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import "../storage/Registry.sol";
import "../libraries/ConfigHelper.sol";

/**
 * The Factory to create new E-Receipt Inventory Trade smart contract instance,
 * Notice: This smart contract must be "isTokenHolderManager" of FBT token smart contracts, hence it can add new Holder for those tokens
 */
contract EReceiptInventoryTradeFactory is Initializable, PausableUpgradeable, OwnableUpgradeable {
    address public registry;

    // Trade smart contract mapped with Trade ID
    mapping(string => address) public tradeContracts;
    mapping(address => bool) public existedTrade;
    mapping(bytes32 => bool) public isExistingReferenceId;

    modifier onlyIfReferenceIdNotInUse(string memory _referenceId) {
        bytes32 identifyHash = keccak256(abi.encodePacked(_referenceId));
        require(
            !isExistingReferenceId[identifyHash],
            'Reference Id is not available'
        );
        _addReferenceId(identifyHash);
        _;
    }

    modifier onlyExistedTrade(address tradeAddress) {
        require(existedTrade[tradeAddress], 'Trade not existed');
        _;
    }

    function _addReferenceId(bytes32 _hashReferenceId) internal {
        isExistingReferenceId[_hashReferenceId] = true;
    }

    function initialize(
        address _registry
    ) public initializer {
        __Pausable_init_unchained();
        __Ownable_init_unchained();
        registry = _registry;
    }

    //-----------------------
    // SEND
    //-----------------------
    // Need to wait util be minned, unable to return contract address
    function newContract(
        string calldata tradeId,
        address[3] calldata tradeAddresses,// TODO note tanlm add buyerPayment tokenaddress to element 2
        uint256[2] calldata tradeTokenIndexs,
        uint256[2] calldata tradeAmounts,
        uint256 expirationTime,
        uint256[2] calldata loanAmounts // 1.principalAmount 2. debtorFee
    ) external whenNotPaused onlyOwner onlyIfReferenceIdNotInUse(tradeId) {
        address[4] memory tradeAddress = [
            tradeAddresses[0], // seller
            tradeAddresses[1], // buyer
            registry,
            tradeAddresses[2]
        ];
        uint256[2] memory tradeNumbers = [tradeAmounts[0], tradeAmounts[1]];

        EReceiptInventoryTrade tradeContract = new EReceiptInventoryTrade();

        tradeContract.initialize(
            tradeAddress,
            tradeTokenIndexs,
            tradeNumbers,
            expirationTime,
            loanAmounts
        );

        // Operator of this Trade: Barter Block
        tradeContract.transferOwnership(_msgSender());

        tradeContracts[tradeId] = address(tradeContract);
        existedTrade[address(tradeContract)] = true;
    }

    //-----------------------
    // CALL
    //-----------------------
    function contractAddressOf(string calldata _tradeId)
    external
    view
    returns (address)
    {
        return tradeContracts[_tradeId];
    }

    function isExistedTrade(address tradeAddress) external view returns (bool) {
        return existedTrade[tradeAddress];
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    //-----------------------
    // Interact with other contract
    //-----------------------
}
