// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/interfaces/IERC20.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol';
import '../../../interfaces/ISecuritizationPool.sol';
import "../../../interfaces/IUntangledERC721.sol";
import "../../../libraries/ConfigHelper.sol";
import '@openzeppelin/contracts/utils/math/SafeMath.sol';

/**
 * UntangledAcceptedInvoiceToken: The representative for a payment responsibility
 */
contract AcceptedInvoiceToken is IUntangledERC721 {
    using ConfigHelper for Registry;
    using SafeMath for uint256;

    bytes32 public constant INVOICE_CREATOR_ROLE = keccak256("INVOICE_CREATOR_ROLE");

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

    mapping(bytes32 => InvoiceMetaData) internal entries;

    /** CONSTRUCTOR */
    function initialize(
        Registry _registry
    ) public initializer {
        __ERC721PresetMinterPauserAutoId_init('Accepted Invoice Token', 'AIT', '');
        registry = _registry;
    }

    //////////////////////////////
    // INTERNAL Functions     ///
    /////////////////////////////

    //** */
    function _generateEntryHash(
        address _payer,
        address _receiver,
        uint256 _fiatAmount,
        uint256 _dueDate,
        uint256 _salt
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_payer, _receiver, _fiatAmount, _dueDate, _salt));
    }

    function _transferTokensFrom(
        address token,
        address from,
        address to,
        uint256 amount
    ) internal returns (bool success) {
        if (registry.getSecuritizationManager().isExistingPools(to))
            to = ISecuritizationPool(to).pot();
        return
            IERC20(token).transferFrom(
                from,
                to,
                amount
            );
    }

    /**
     * Mints a unique LAT token and inserts the associated issuance into
     * the loan registry, if the calling address is authorized to do so.
     */
    function create(
        address[2] memory addressParams, // 0-payer, 1-receiver
        uint256 _fiatAmount,
        address _fiatTokenAddress,
        uint256 _dueDate,
        uint256 salt,
        uint8 assetPurpose
    ) public whenNotPaused returns (uint256) {
        require(
            hasRole(MINTER_ROLE, _msgSender()),
            'not permission to create token'
        );
        require(_fiatTokenAddress != address(0x0), 'Invalid fiat token');

        return
            _createAIT(
                addressParams[0],
                addressParams[1],
                _fiatAmount,
                _fiatTokenAddress,
                _dueDate,
                salt,
                0,
                assetPurpose
            );
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
        require(
            hasRole(INVOICE_CREATOR_ROLE, _msgSender()),
            'not permission to create token'
        );

        uint8 assetPurpose = riskScoreIdxsAndAssetPurpose[_fiatAmount.length - 1];
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

    function updateFiatAmount(
        uint256 tokenId,
        uint256 fiatAmount,
        uint8[2] calldata signaturesV, // 1-beneficiarySignatureV, 2-payerSignatureV
        bytes32[2] calldata signaturesR, // 1-beneficiarySignatureR, 2-payerSignatureR
        bytes32[2] calldata signaturesS // 1-beneficiarySignatureS, 2-payerSignatureS
    ) external {
        //Todo Verify signature

        require(!isPaid(tokenId), 'AIT: Token has been paid');
        require(entries[bytes32(tokenId)].paidAmount < fiatAmount, 'Paid amount is already greater');
        require(entries[bytes32(tokenId)].fiatAmount != fiatAmount, 'Same fiat amount');

        InvoiceMetaData storage metadata = entries[bytes32(tokenId)];
        metadata.fiatAmount = fiatAmount;
    }

    // Do payment for the invoice
    // @TODO: Issue with same event name from two contracts (https://github.com/trufflesuite/truffle/issues/1729)
    function pay(uint256 tokenId, address payer) public returns (bool) {
        // require(msg.sender == entries[bytes32(tokenId)].payer, 'Caller must be payer');
        require(!isPaid(tokenId), 'Invoice is already paid');

        // address fiatTokenAddress = ERC20TokenRegistry(contractRegistry().get(ERC20_TOKEN_REGISTRY)).getTokenAddressByIndex(
        //     entries[bytes32(tokenId)].fiatTokenIndex
        // );

        // ERC20Mintable token = ERC20Mintable(entries[bytes32(tokenId)].fiatTokenAddress);

        // require(token.balanceOf(entries[bytes32(tokenId)].payer) >= entries[bytes32(tokenId)].fiatAmount, 'Not enough balance');

        // (bool success, ) = entries[bytes32(tokenId)].fiatTokenAddress.call(
        //   abi.encodePacked(token.burn.selector,  abi.encode(entries[bytes32(tokenId)].payer, entries[bytes32(tokenId)].fiatAmount))
        // );

        // if (!success) {
        _transferTokensFrom(
            entries[bytes32(tokenId)].fiatTokenAddress,
            payer,
            ownerOf(tokenId),
            entries[bytes32(tokenId)].fiatAmount
        );
        // }

        InvoiceMetaData storage metadata = entries[bytes32(tokenId)];
        metadata.paidAmount = metadata.paidAmount.add(entries[bytes32(tokenId)].fiatAmount);
        if (isPaid(tokenId)) {
            super._burn(tokenId);
        }
        return true;
    }

    function partialPayment(
        uint256 tokenId,
        address payer,
        uint256 payAmount
    ) public {
        require(!isPaid(tokenId), 'AIT: Invoice is already paid');

        InvoiceMetaData storage metadata = entries[bytes32(tokenId)];
        // address fiatTokenAddress = ERC20TokenRegistry(contractRegistry().get(ERC20_TOKEN_REGISTRY)).getTokenAddressByIndex(
        //     metadata.fiatTokenIndex
        // );
        // require(msg.sender == metadata.payer, 'Caller must be payer');

        // ERC20Mintable token = ERC20Mintable(entries[bytes32(tokenId)].fiatTokenAddress);

        // require(token.balanceOf(metadata.payer) >= payAmount, 'Not enough balance');

        uint256 fiatAmountRemain = 0;
        if (metadata.fiatAmount > payAmount) {
            fiatAmountRemain = metadata.fiatAmount - payAmount;
        }

        // (bool success, ) = metadata.fiatTokenAddress.call(
        //   abi.encodePacked(token.burn.selector,  abi.encode(metadata.payer, payAmount))
        // );

        // if (!success) {
        // Transfer
        _transferTokensFrom(metadata.fiatTokenAddress, payer, ownerOf(tokenId), payAmount);
        // }

        if (fiatAmountRemain == 0) {
            metadata.paidAmount = metadata.paidAmount.add(payAmount);
            super._burn(tokenId);
        } else {
            metadata.fiatAmount = fiatAmountRemain;
        }
    }

    function payInBatch(uint256[] calldata tokenIds, uint256[] calldata payAmounts) external returns (bool) {
        require(tokenIds.length == payAmounts.length, 'Length miss match');

        for (uint256 i = 0; i < tokenIds.length; ++i) {
            require(!isPaid(tokenIds[i]), 'AIT: Invoice is already paid');

            InvoiceMetaData storage metadata = entries[bytes32(tokenIds[i])];

            ERC20PresetMinterPauser token = ERC20PresetMinterPauser(entries[bytes32(tokenIds[i])].fiatTokenAddress);

            require(token.balanceOf(msg.sender) >= payAmounts[i], 'Not enough balance');

            uint256 fiatAmountRemain = 0;
            if (metadata.fiatAmount > payAmounts[i]) {
                fiatAmountRemain = metadata.fiatAmount - payAmounts[i];
            }

            _transferTokensFrom(metadata.fiatTokenAddress, msg.sender, ownerOf(tokenIds[i]), payAmounts[i]);

            if (fiatAmountRemain == 0) {
                metadata.paidAmount = metadata.paidAmount.add(payAmounts[i]);
                super._burn(tokenIds[i]);
            } else {
                metadata.fiatAmount = fiatAmountRemain;
            }

            emit LogRepayment(tokenIds[i], msg.sender, ownerOf(tokenIds[i]), payAmounts[i], metadata.fiatTokenAddress);
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
        uint8 _assetPurpose
    ) internal returns (uint256) {
        bytes32 entryHash = _generateEntryHash(payer, receiver, _fiatAmount, _dueDate, salt);

        entries[entryHash] = InvoiceMetaData({
            payer: payer,
            fiatAmount: _fiatAmount,
            paidAmount: 0,
            fiatTokenAddress: _fiatTokenAddress,
            dueDate: _dueDate,
            createdAt: block.timestamp,
            riskScoreIdx: _riskScoreIdx,
            assetPurpose: Configuration.ASSET_PURPOSE(_assetPurpose)
        });

        super._mint(receiver, uint256(entryHash));

        return uint256(entryHash);
    }

    function getExpectedRepaymentValues(uint256 tokenId, uint256 timestamp) public view returns (uint256, uint256) {
        return (entries[bytes32(tokenId)].fiatAmount.sub(entries[bytes32(tokenId)].paidAmount), 0);
    }

    function getTotalExpectedRepaymentValue(uint256 agreementId, uint256 timestamp)
        public
        override
        view
        returns (uint256 expectedRepaymentValue)
    {
        uint256 principalAmount;
        uint256 interestAmount;
        (principalAmount, interestAmount) = getExpectedRepaymentValues(agreementId, timestamp);
        expectedRepaymentValue = principalAmount.add(interestAmount);
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

    function details(uint256 tokenId)
        public
        view
        returns (
            address payer,
            uint256 fiatAmount,
            uint256 paidAmount,
            address fiatTokenAddress,
            uint256 dueDate,
            uint256 createdAt
        )
    {
        InvoiceMetaData storage metadata = entries[bytes32(tokenId)];
        payer = metadata.payer;
        fiatAmount = metadata.fiatAmount;
        paidAmount = metadata.paidAmount;
        fiatTokenAddress = metadata.fiatTokenAddress;
        dueDate = metadata.dueDate;
        createdAt = metadata.createdAt;
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
