// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/interfaces/IERC20.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol';
import '../../../interfaces/ISecuritizationPool.sol';
import '../../../interfaces/IUntangledERC721.sol';
import '../../../libraries/ConfigHelper.sol';

/**
 * UntangledAcceptedInvoiceToken: The representative for a payment responsibility
 */
contract AcceptedInvoiceToken is IUntangledERC721 {
    using ConfigHelper for Registry;

    bytes32 public constant INVOICE_CREATOR_ROLE = keccak256('INVOICE_CREATOR_ROLE');

    struct InvoiceMetaData {
        address payer;
        uint256 fiatAmount;
        uint256 paidAmount;
        address fiatTokenAddress;
        uint256 dueDate;
        uint256 createdAt;
        uint8 riskScoreIdx;
        Configuration.ASSET_PURPOSE assetPurpose;
    }

    mapping(bytes32 => InvoiceMetaData) public entries;

    /** CONSTRUCTOR */
    function initialize(
        Registry _registry,
        string memory name,
        string memory symbol,
        string memory baseTokenURI
    ) public initializer {
        __UntangledERC721__init(name, symbol, baseTokenURI);
        registry = _registry;
    }

    //////////////////////////////
    // PRIVATE Functions     ///
    /////////////////////////////

    //** */
    function _generateEntryHash(
        address _payer,
        address _receiver,
        uint256 _fiatAmount,
        uint256 _dueDate,
        uint256 _salt
    ) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(_payer, _receiver, _fiatAmount, _dueDate, _salt));
    }

    function _transferTokensFrom(
        address token,
        address from,
        address to,
        uint256 amount
    ) private {
        if (registry.getSecuritizationManager().isExistingPools(to)) to = ISecuritizationPool(to).pot();
        require(IERC20(token).transferFrom(from, to, amount), 'AcceptedInvoiceToken: transferFrom failure');
    }

    function createBatch(
        address[] calldata addressPayerAndReceiver,
        // address[] calldata addressReceiver,
        uint256[] calldata _fiatAmount,
        address[] calldata _fiatTokenAddress,
        uint256[] calldata _dueDate,
        uint256[] calldata salt,
        uint8[] calldata riskScoreIdxsAndAssetPurpose //[...riskScoreIdxs, assetPurpose]
    ) external whenNotPaused {
        require(hasRole(INVOICE_CREATOR_ROLE, _msgSender()), 'not permission to create token');
        // fail to cached the array length due to stack too deep
        // uint256 fiatAmountLength = _fiatAmount.length;
        Configuration.ASSET_PURPOSE assetPurpose = Configuration.ASSET_PURPOSE(
            riskScoreIdxsAndAssetPurpose[_fiatAmount.length - 1]
        );
        for (uint256 i = 0; i < _fiatAmount.length; ++i) {
            _createAIT(
                addressPayerAndReceiver[i],
                addressPayerAndReceiver[i + _fiatAmount.length],
                _fiatAmount[i],
                _fiatTokenAddress[i],
                _dueDate[i],
                salt[i],
                riskScoreIdxsAndAssetPurpose[i],
                assetPurpose
            );
        }
    }

    function payInBatch(uint256[] calldata tokenIds, uint256[] calldata payAmounts) external returns (bool) {
        uint256 tokenIdsLength = tokenIds.length;
        require(tokenIdsLength == payAmounts.length, 'Length miss match');

        for (uint256 i = 0; i < tokenIdsLength; ++i) {
            require(!isPaid(tokenIds[i]), 'AIT: Invoice is already paid');

            InvoiceMetaData storage metadata = entries[bytes32(tokenIds[i])];

            ERC20PresetMinterPauser token = ERC20PresetMinterPauser(entries[bytes32(tokenIds[i])].fiatTokenAddress);

            require(token.balanceOf(msg.sender) >= payAmounts[i], 'Not enough balance');

            uint256 fiatAmountRemain = 0;
            if (metadata.fiatAmount > (payAmounts[i] + metadata.paidAmount)) {
                fiatAmountRemain = metadata.fiatAmount - metadata.paidAmount - payAmounts[i];
            }

            address receiver = ownerOf(tokenIds[i]);

            _transferTokensFrom(metadata.fiatTokenAddress, msg.sender, receiver, payAmounts[i]);

            if (fiatAmountRemain == 0) {
                metadata.paidAmount += payAmounts[i];
                super._burn(tokenIds[i]);
            } else {
                metadata.paidAmount += payAmounts[i];
            }

            emit LogRepayment(tokenIds[i], msg.sender, receiver, payAmounts[i], metadata.fiatTokenAddress);
        }

        emit LogRepayments(tokenIds, msg.sender, payAmounts);
        return true;
    }

    /**=--------- */
    // CALL
    /**=--------- */
    function _createAIT(
        address payer,
        address receiver,
        uint256 _fiatAmount,
        address _fiatTokenAddress,
        uint256 _dueDate,
        uint256 salt,
        uint8 _riskScoreIdx,
        Configuration.ASSET_PURPOSE _assetPurpose
    ) private returns (uint256) {
        bytes32 entryHash = _generateEntryHash(payer, receiver, _fiatAmount, _dueDate, salt);

        entries[entryHash] = InvoiceMetaData({
            payer: payer,
            fiatAmount: _fiatAmount,
            paidAmount: 0,
            fiatTokenAddress: _fiatTokenAddress,
            dueDate: _dueDate,
            createdAt: block.timestamp,
            riskScoreIdx: _riskScoreIdx,
            assetPurpose: _assetPurpose
        });

        mint(receiver, uint256(entryHash));

        return uint256(entryHash);
    }

    function getExpectedRepaymentValues(uint256 tokenId, uint256) public view returns (uint256, uint256) {
        return (entries[bytes32(tokenId)].fiatAmount - entries[bytes32(tokenId)].paidAmount, 0);
    }

    function getTotalExpectedRepaymentValue(uint256 agreementId, uint256 timestamp)
        public
        view
        override
        returns (uint256 expectedRepaymentValue)
    {
        uint256 principalAmount;
        uint256 interestAmount;
        (principalAmount, interestAmount) = getExpectedRepaymentValues(agreementId, timestamp);
        expectedRepaymentValue = principalAmount + interestAmount;
    }

    function getExpirationTimestamp(uint256 _tokenId) public view override returns (uint256) {
        return entries[bytes32(_tokenId)].dueDate;
    }

    function getInterestRate(uint256 _tokenId) public pure override returns (uint256) {
        return 0;
    }

    function getAssetPurpose(uint256 _tokenId) public view override returns (Configuration.ASSET_PURPOSE) {
        return entries[bytes32(_tokenId)].assetPurpose;
    }

    function getRiskScore(uint256 _tokenId) public view override returns (uint8) {
        return entries[bytes32(_tokenId)].riskScoreIdx;
    }

    function getFiatAmount(uint256 tokenId) public view returns (uint256) {
        return entries[bytes32(tokenId)].fiatAmount;
    }

    function isPaid(uint256 tokenId) public view returns (bool) {
        return entries[bytes32(tokenId)].fiatAmount <= entries[bytes32(tokenId)].paidAmount;
    }

    event LogRepayment(
        uint256 indexed _tokenId,
        address indexed _payer,
        address indexed _beneficiary,
        uint256 _amount,
        address _token
    );

    event LogRepayments(uint256[] _tokenIds, address _payer, uint256[] _amounts);
}
