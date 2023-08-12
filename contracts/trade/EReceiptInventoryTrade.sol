// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../storage/Registry.sol";
import "../libraries/ConfigHelper.sol";
import '@openzeppelin/contracts-upgradeable/interfaces/IERC1155ReceiverUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155ReceiverUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract EReceiptInventoryTrade is Initializable, PausableUpgradeable, OwnableUpgradeable, ERC1155ReceiverUpgradeable {
    using SafeMath for uint256;
    using ConfigHelper for Registry;

    Registry public registry;

    struct Fees {
        uint256 amount;
        address erc20Token;
        address beneficiary;
    }

    // bool internal isHasSetupMandatoryFee = false;
    bool public isRefundedOptionalFees = false;

    // the existence of beneficiary
    mapping(address => bool) public isFeePayers;
    address[] public feePayers;

    // Optional Area
    mapping(bytes32 => bool) public isOptionalFeeTypeIds;
    bytes32[] public optionalFeeTypeIds;

    // Mandatory Area
    mapping(bytes32 => bool) public isMandatoryFeeTypeIds;
    bytes32[] public mandatoryFeeTypeIds;

    // index -> true/false
    mapping(address => bool) public isFeeTokens;
    address[] public feeTokens;

    mapping(address => bool) public isMandatoryFeeTokens;
    address[] public mandatoryFeeTokens;

    // payer => (fee type id => fee details list)
    // For now only support 1 beneficiary for 1 type of fee from each payers
    mapping(address => mapping(bytes32 => Fees)) public requiredFees;
    mapping(address => mapping(bytes32 => bool)) public hasSetupFees;

    // payer => (token fee index => expected amount)
    mapping(address => mapping(address => uint256)) public tokenFeeAmounts;
    // payer => (token fee index => paid amount)
    mapping(address => mapping(address => uint256)) public paidTokenFeeAmounts;

    // payer => (token fee => released amount)
    mapping(address => mapping(address => uint256)) releasedTokenAmounts;

    //From EReceiptInventoryTrade contract
    struct TradePayment {
        uint256 tokenIndex;
        uint256 amount;
        uint256 paidAmount;
    }

    struct Payment {
        IERC20 token;
        uint256 amount;
        uint256 paidAmount;
    }

    // Seller
    address public seller;
    // Buyer
    address public buyer;

    uint256 public expirationTime;
    uint256 public creationTime;
    uint256 public principalAmount;
    uint256 public debtorFee;
    bytes32 public loanAgreementId;

    enum State {Initiated, CompletedPayment, Completed, Aborted, Expired}
    State public state;

    // Buyer expected&completed payments
    Payment public buyerPayment;

    // Seller completed&completed payments
    TradePayment public sellerPayment;
    //End EReceiptInventoryTrade contract

    //-------------------------------------------
    // Events
    //-------------------------------------------

    //-------------------------------------------
    // Modifiers
    //-------------------------------------------
    modifier onlyFeePayer {
        require(
            isFeePayers[_msgSender()],
            "Fees: Only payer can call to this function."
        );
        _;
    }

    // modifier onlyIfHasSetupMandatoryFee {
    //     require(isHasSetupMandatoryFee, "Fees: Requires setting up fees before can go any further.");
    //     _;
    // }

    modifier onlyUncompletedTrade() {
        require(
            state != State.Completed &&
            state != State.Aborted &&
            state != State.Expired,
            'Only for uncompleted trade'
        );
        _;
    }

    //==============================
    // Internal functions
    //==============================


    function initialize(
        address[4] memory tradeAddresses, // 0: seller, 1: buyer, 2: contractRegistry, 3: buyerPayment token address // TODO Note: buyerPayment token address
        uint256[2] memory tradeTokenIndexs, // 0: cat, 1: cma // TODO not remove index0, not use. use 0x0000 for undefined
        uint256[2] memory tradeNumbers, // 0: amount fat, 1: amount cma
        uint256 _expirationTime,
        uint256[2] memory loanAmounts // 0: principalAmount, 2: debtorFee
    ) public initializer {
        __Pausable_init_unchained();
        __Ownable_init_unchained();

        seller = tradeAddresses[0];
        buyer = tradeAddresses[1];
        registry = Registry(tradeAddresses[2]);

        buyerPayment = Payment({
        token: IERC20(tradeAddresses[3]),
        amount: tradeNumbers[0],
        paidAmount: 0
        });

        sellerPayment = TradePayment({
        tokenIndex: tradeTokenIndexs[1],
        amount: tradeNumbers[1],
        paidAmount: 0
        });

        creationTime = block.timestamp;
        principalAmount = loanAmounts[0];
        debtorFee = loanAmounts[1];
        expirationTime = _expirationTime;
        state = State.Initiated;
    }

    function _isOptionalFeeType(uint256 id) internal view returns (bool) {
        return isOptionalFeeTypeIds[bytes32(id)];
    }

    function _isMandatoryFeeType(uint256 id) internal view returns (bool) {
        return isMandatoryFeeTypeIds[bytes32(id)];
    }

    function _addPayer(address account) internal {
        if (!isFeePayers[account]) {
            feePayers.push(account);
            isFeePayers[account] = true;
        }
    }

    function _addOptionalFeeTypeId(uint256 id) internal {
        if (!_isOptionalFeeType(id)) {
            optionalFeeTypeIds.push(bytes32(id));
            isOptionalFeeTypeIds[bytes32(id)] = true;
        }
    }

    function _addMandatoryFeeTypeId(uint256 id) internal {
        if (!_isMandatoryFeeType(id)) {
            mandatoryFeeTypeIds.push(bytes32(id));
            isMandatoryFeeTypeIds[bytes32(id)] = true;
        }
    }

    function _addFeeToken(address _erc20Token) internal {
        if (!isFeeTokens[_erc20Token]) {
            feeTokens.push(_erc20Token);
            isFeeTokens[_erc20Token] = true;
        }
    }

    function _addMandatoryFeeToken(address _erc20Token) internal {
        if (!isMandatoryFeeTokens[_erc20Token]) {
            mandatoryFeeTokens.push(_erc20Token);
            isMandatoryFeeTokens[_erc20Token] = true;
        }
    }

    function _transferFeeToBeneficiary(
        address payer,
        uint256 amount,
        address erc20TokenAddress,
        address beneficiary
    ) internal {
        IERC20(erc20TokenAddress).transfer(beneficiary, amount);

        _newFeeReleaseHasCompleted(payer, amount, erc20TokenAddress);
    }

    function _transferTokensFrom(
        address token,
        address from,
        address to,
        uint256 amount
    ) internal returns (bool success) {
        return
        IERC20(token).transferFrom(
            from,
            to,
            amount
        );
    }

    /**
    * Setup other additional fees for trading
    */
    function _setupFee(
        uint256 _feeId,
        address _payer,
        uint256 _amount,
        address _erc20Token,
        address _beneficiary,
        bool _isMandatory
    ) internal {
        Fees memory fee = Fees({
        amount: _amount,
        erc20Token: _erc20Token,
        beneficiary: _beneficiary
        });

        requiredFees[_payer][bytes32(_feeId)] = fee;
        hasSetupFees[_payer][bytes32(_feeId)] = true;

        _addPayer(_payer);
        _addFeeToken(_erc20Token);
        _setupNewFeePayment(_payer, _amount, _erc20Token);
        if (_isMandatory) {
            _addMandatoryFeeTypeId(_feeId);
            _addMandatoryFeeToken(_erc20Token);
        } else {
            _addOptionalFeeTypeId(_feeId);
        }
    }

    function _newFeePaymentHasCompleted(
        address _payer,
        uint256 _amount,
        address _erc20Token
    ) internal {
        uint256 totalPaid = paidTokenFeeAmounts[_payer][_erc20Token].add(_amount);
        paidTokenFeeAmounts[_payer][_erc20Token] = totalPaid;
    }

    function _newFeeReleaseHasCompleted(
        address _payer,
        uint256 _amount,
        address _erc20TokenAddress
    ) internal {
        uint256 totalReleased = releasedTokenAmounts[_payer][_erc20TokenAddress].add(
            _amount
        );
        releasedTokenAmounts[_payer][_erc20TokenAddress] = totalReleased;
    }

    function _setupNewFeePayment(
        address _payer,
        uint256 _amount,
        address _erc20Token
    ) internal {
        uint256 totalRequiredAmount = tokenFeeAmounts[_payer][_erc20Token].add(
            _amount
        );
        tokenFeeAmounts[_payer][_erc20Token] = totalRequiredAmount;
    }

    function _doFeePayment(address _payer, uint256 _amount, address _erc20Token)
    internal
    {
        require(_erc20Token != address(0), "MultipleFeesTrading: Invalid token address - NULL address.");
        if (_transferTokensFrom(_erc20Token, _payer, address(this), _amount)) {
            _newFeePaymentHasCompleted(_payer, _amount, _erc20Token);
        }
    }

    function _isCompletedFeePaymentWithToken(address _payer, address _erc20Token)
    internal
    view
    returns (bool)
    {
        return tokenFeeAmounts[_payer][_erc20Token] <= paidTokenFeeAmounts[_payer][_erc20Token];
    }

    // Refunds all optional tokens fee when Trade instance is ABORTED or EXPIRED
    function _refundOptionalFees() internal {
        uint256 payerListLength = feePayers.length;
        uint256 feeTypesLength = optionalFeeTypeIds.length;

        for (uint256 i = 0; i < payerListLength; i++) {
            for (uint256 j = 0; j < feeTypesLength; j++) {
                if (hasSetupFees[feePayers[i]][optionalFeeTypeIds[j]]) {
                    Fees memory fee = requiredFees[feePayers[i]][optionalFeeTypeIds[j]];
                    // If paid amount greater than the released amount (IN > OUT)
                    if (
                        paidTokenFeeAmounts[feePayers[i]][fee.erc20Token] >
                        releasedTokenAmounts[feePayers[i]][fee.erc20Token]
                    ) {
                        uint256 remainAmount = paidTokenFeeAmounts[feePayers[i]][fee
                        .erc20Token]
                        .sub(releasedTokenAmounts[feePayers[i]][fee.erc20Token]);

                        _transferFeeToBeneficiary(
                            feePayers[i],
                            remainAmount,
                            fee.erc20Token,
                            feePayers[i]
                        );
                    }
                }
            }
        }
        isRefundedOptionalFees = true;
    }

    // Release optional fees whenever instance has been expired/aborted
    function _releaseOptionalFees() internal {
        uint256 feeTypesLength = optionalFeeTypeIds.length;
        uint256 payerListLength = feePayers.length;

        for (uint256 j = 0; j < feeTypesLength; j++) {
            for (uint256 i = 0; i < payerListLength; i++) {
                if (hasSetupFees[feePayers[i]][optionalFeeTypeIds[j]]) {
                    Fees memory fee = requiredFees[feePayers[i]][optionalFeeTypeIds[j]];
                    if (
                        paidTokenFeeAmounts[feePayers[i]][fee.erc20Token] >
                        releasedTokenAmounts[feePayers[i]][fee.erc20Token]
                    ) {
                        uint256 remainAmount = paidTokenFeeAmounts[feePayers[i]][fee.erc20Token]
                        .sub(releasedTokenAmounts[feePayers[i]][fee.erc20Token]);
                        if (remainAmount > fee.amount) {
                            _transferFeeToBeneficiary(
                                feePayers[i],
                                fee.amount,
                                fee.erc20Token,
                                fee.beneficiary
                            );

                            _transferFeeToBeneficiary(
                                feePayers[i],
                                remainAmount - fee.amount,
                                fee.erc20Token,
                                feePayers[i]
                            );
                        } else {
                            _transferFeeToBeneficiary(
                                feePayers[i],
                                remainAmount,
                                fee.erc20Token,
                                fee.beneficiary
                            );
                        }
                    }
                }
            }
        }

    }

    // function _releaseMandatoryFees() internal {
    //     uint feeTypesLength = mandatoryFeeTypeIds.length;
    //     uint payerListLength = feePayers.length;

    //     for(uint j = 0; j < feeTypesLength; j++) {
    //         for (uint i = 0; i < payerListLength; i++) {
    //             if (hasSetupFees[feePayers[i]][mandatoryFeeTypeIds[j]]) {
    //                 Fees memory fee = requiredFees[feePayers[i]][mandatoryFeeTypeIds[j]];
    //                 if (paidTokenFeeAmounts[feePayers[i]][fee.token] > releasedTokenAmounts[feePayers[i]][fee.token]) {
    //                     uint remainAmount = paidTokenFeeAmounts[feePayers[i]][fee.token].sub(releasedTokenAmounts[feePayers[i]][fee.token]);
    //                     if (remainAmount >= fee.amount) {
    //                         _transferFeeToBeneficiary(feePayers[i], fee.amount, fee.token, fee.beneficiary);
    //                     } else {
    //                         _transferFeeToBeneficiary(feePayers[i], remainAmount, fee.token, fee.beneficiary);
    //                     }
    //                 }
    //             }
    //         }
    //     }
    // }

    /**
    * Transfer fee to corresponding beneficiary
    */
    function _transferFeeToBeneficiaries() internal {
        // _releaseMandatoryFees();
        if (!isRefundedOptionalFees) {
            _releaseOptionalFees();
        }
    }

    //-------------------------------------------
    // External functions
    //-------------------------------------------
    /**
    * Setup mandatory fee, which user need to pay regardless what happened with Trade instance
    */
    // function setupMandatoryFee(
    //     uint _feeId,
    //     address _payer,
    //     uint _amount,
    //     address _token,
    //     address _beneficiary
    // )
    //     public
    //     onlyOwner
    // {
    //     _setupFee(_feeId, _payer, _amount, _token, _beneficiary, true);
    //     isHasSetupMandatoryFee = true;
    // }

    function setupOptionalFee(
        uint256 _feeId,
        address _payer,
        uint256 _amount,
        address _erc20Token,
        address _beneficiary
    ) public onlyOwner {
        _setupFee(_feeId, _payer, _amount, _erc20Token, _beneficiary, false);
    }

    function removeOptionalFee(
        uint256 _feeId,
        address _payer,
        address _erc20Token
    )  public onlyOwner {
        require(paidTokenFeeAmounts[_payer][_erc20Token] == 0, "Payer already paid for fee");

        delete requiredFees[_payer][bytes32(_feeId)];
        delete hasSetupFees[_payer][bytes32(_feeId)];
        delete tokenFeeAmounts[_payer][_erc20Token];
        delete isOptionalFeeTypeIds[bytes32(_feeId)];

        for (uint i = 0; i < optionalFeeTypeIds.length; ++i) {
            if (optionalFeeTypeIds[i] == bytes32(_feeId)) {

                // Remove i element from optionalFeeTypeIds
                for (uint index = i; index < optionalFeeTypeIds.length-1; index++){
                    optionalFeeTypeIds[index] = optionalFeeTypeIds[index+1];
                }
                optionalFeeTypeIds.pop();

                break;
            }
        }
    }

    //---------------
    // CALL
    //---------------

    // Have account completed fee payment for his trade, both Mandatory and Optional
    function isCompletedFeesPayment(address account)
    public
    view
    returns (bool)
    {
        uint256 feeTokensLength = feeTokens.length;
        bool isCompleted = true;
        for (uint256 i = 0; i < feeTokensLength; i++) {
            if (!_isCompletedFeePaymentWithToken(account, feeTokens[i])) {
                isCompleted = false;
                break;
            }
        }
        return isCompleted;
    }

    // function isSatisfiedMandatoryFeePayment(address account) {
    //     uint mandatoryFeeIdsLength = mandatoryFeeTypeIds.length;
    //     for(uint i = 0; i < mandatoryFeeIdsLength; i++) {

    //     }
    // }

    function feePaymentStatus(address account)
    public
    view
    returns (address[] memory, uint256[] memory, uint256[] memory)
    {
        uint256 feeTokensLength = feeTokens.length;
        address[] memory feeTokenAddresses = new address[](feeTokensLength);
        uint256[] memory expectedAmounts = new uint256[](feeTokensLength);
        uint256[] memory paidAmounts = new uint256[](feeTokensLength);

        for (uint256 i = 0; i < feeTokensLength; i++) {
            feeTokenAddresses[i] = feeTokens[i];
            expectedAmounts[i] = tokenFeeAmounts[account][feeTokens[i]];
            paidAmounts[i] = paidTokenFeeAmounts[account][feeTokens[i]];
        }

        return (feeTokenAddresses, expectedAmounts, paidAmounts);
    }

    function _inState(State _state) internal view returns (bool) {
        return (state == _state);
    }

    // Process checking the payment from seller and buyer to change Trade's state
    function _paymentStatusCheck() internal {
        if (
            buyerPayment.paidAmount >= buyerPayment.amount &&
            sellerPayment.paidAmount >= sellerPayment.amount &&
            isCompletedFeesPayment(seller) &&
            isCompletedFeesPayment(buyer)
        ) {
            state = State.CompletedPayment;
        } else {
            state = State.Initiated;
        }
    }

    function _newFiatPayment(uint256 _amount) internal {
        buyerPayment.paidAmount = SafeMath.add(
            buyerPayment.paidAmount,
            _amount
        );
    }

    function _newCommodityPayment(uint256 _amount) internal {
        sellerPayment.paidAmount = SafeMath.add(
            sellerPayment.paidAmount,
            _amount
        );
    }

    //==============================
    // External functions
    //==============================
    //-------------------
    // CALL
    //-------------------

    function expirationTimeLeft() public view returns (uint256) {
        return SafeMath.sub(expirationTime, SafeMath.sub(block.timestamp, creationTime));
    }

    function isExpired() public view returns (bool) {
        if (expirationTime > SafeMath.sub(block.timestamp, creationTime)) {
            return false;
        } else {
            return true;
        }
    }

    function isCompleted() public view returns (bool) {
        return (state == State.Completed);
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
    external returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
    external returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }


    //--------------------------
    // SEND
    //--------------------------
    //=----------------
    // Function for Controllers
    //=----------------
    function setExpirationTime(uint256 _expirationTime)
    public
    onlyOwner
    {
        expirationTime = _expirationTime;
    }

    function updateCommodityTokenIndex(uint256 _newIndex)
    public
    onlyOwner
    {
        sellerPayment.tokenIndex = _newIndex;
    }

    function updateFiatTokenAddress(address _erc20Token)
    public
    onlyOwner
    {
        buyerPayment.token = IERC20(_erc20Token);
    }

    function updateBuyerPaymentAmount(uint256 newPaymentAmount)
    external
    onlyOwner
    {
        buyerPayment.amount = newPaymentAmount;
        _paymentStatusCheck();
    }

    function updateSellerPaymentAmount(uint256 newPaymentAmount)
    external
    onlyOwner
    {
        sellerPayment.amount = newPaymentAmount;
        _paymentStatusCheck();
    }

    function checkExpirationTime() public onlyOwner {
        if (isExpired()) {
            state = State.Expired;
        }
    }

    function paymentStatusCheck() public {
        _paymentStatusCheck();
    }

    function payFee(address payer, uint256 amount, address _erc20Token) public {
        require(_inState(State.Initiated), 'Only for uncompleted trade');

        _doFeePayment(payer, amount, _erc20Token);
        _paymentStatusCheck();
    }

    /**
     */
    function submitExpirationRelease() public onlyOwner {
        require(
            _inState(State.Expired) || isExpired(),
            'Only for expired trade'
        );

        returnPaymentAmountAndCollectFee();
    }

    /**
     * NOTICE: Must call approve first
     * @dev Function only able to be called by Trade Contract's controller
     */
    function doFiatPayment(uint256 _amount) public {
        require(_inState(State.Initiated), 'Only for uncompleted trade');

        if (
            buyerPayment.token.transferFrom(buyer,
                address(this),
                _amount
            )
        ) {
            _newFiatPayment(_amount);
        }
        _paymentStatusCheck();
    }

    function doCommodityPayment(uint256 _amount) public {
        require(_inState(State.Initiated), 'Only for uncompleted trade');

        registry.getCollateralManagementToken()
        .safeTransferFrom(
            seller,
            address(this),
            sellerPayment.tokenIndex,
            _amount,
            "0x0"
        );
        _newCommodityPayment(_amount);
        _paymentStatusCheck();
    }

    function initLoanForTrade(
        address creditor,
        address[6] calldata orderAddresses, // 1-repayment router, 2-debtor, 3-termcontract, 4-principalTokenAddress, 5-relayer, 6-priceFeeOperator
        uint256[7] calldata orderValues, // 1-salt, 2-principalAmount, 3-creditorFee, 4-debtorFee, 5-expirationTimestampInSec, 6-minCR, 7-liquidationRatio
        bytes32[1] calldata orderBytes32, // 1-termsContractParameters
        bytes16[1] calldata orderBytes16, // 1-collateralInfoParameters
        address[5] calldata debtorFeeBeneficiaries,
        address[5] calldata creditorFeeBeneficiaries,
        uint256[5] calldata debtorFeeAmounts,
        uint256[5] calldata creditorFeeAmounts
    ) external onlyOwner {
        loanAgreementId = registry.getInventoryLoanKernel()
            ._fillDebtOrder(
                creditor,
                buyer,
                principalAmount,
                orderAddresses,
                orderValues,
                orderBytes32,
                orderBytes16,
                debtorFeeBeneficiaries,
                creditorFeeBeneficiaries,
                debtorFeeAmounts,
                creditorFeeAmounts
            );
        swap();
    }

    // Owner interact with Trade's state
    /// @dev Function only able to be called by contract Owner. Obviously participants only able to complete the payments
    // if Trade Controller has set up fee
    function swap() public onlyOwner {
        require(_inState(State.CompletedPayment), 'Not completed payment');

        bool isEmbeddedFlow = principalAmount > 0;

        IERC20 erc20 = buyerPayment.token;

        if (isEmbeddedFlow) {
            erc20.transfer(seller, buyerPayment.amount + principalAmount - debtorFee);
        } else {
            erc20.transfer(seller, buyerPayment.amount);
        }

        // return redundant paid amount to buyer
        if (buyerPayment.paidAmount > buyerPayment.amount) {
            erc20.transfer(
                buyer,
                buyerPayment.paidAmount.sub(buyerPayment.amount)
            );
        }

        CollateralManagementToken erc1155 = registry.getCollateralManagementToken();

        if (!isEmbeddedFlow) {
            erc1155.safeTransferFrom(
                address(this),
                buyer,
                sellerPayment.tokenIndex,
                sellerPayment.amount,
                "0x0"
            );
        }

        // return redundant paid amount to seller
        if (sellerPayment.paidAmount > sellerPayment.amount) {
            erc1155.safeTransferFrom(
                address(this),
                seller,
                sellerPayment.tokenIndex,
                sellerPayment.paidAmount.sub(sellerPayment.amount),
                "0x0"
            );
        }

        _transferFeeToBeneficiaries();

        state = State.Completed;
    }

    /// @dev Function is not able to be called by normal user
    function abortTrade() public onlyOwner onlyUncompletedTrade {
        returnPaymentAmountAndCollectFee();

        state = State.Aborted;
    }

    function returnPaymentAmountAndCollectFee() internal {
        // Return fiat tokens to buyer
        buyerPayment.token
        .transfer(buyer, buyerPayment.paidAmount);

        // Return cma tokens to seller
        CollateralManagementToken erc1155 = registry.getCollateralManagementToken();
        erc1155.safeTransferFrom(
            address(this),
            seller,
            sellerPayment.tokenIndex,
            sellerPayment.paidAmount,
            "0x0"
        );

        // Collect fee
        _transferFeeToBeneficiaries();
    }

    //=-----------------------------------------------------------------------
    // Functions for participants of Trade
    //=-----------------------------------------------------------------------
    //=-- Query payment state from parties
    function getContractState() public view returns (uint8) {
        return uint8(state);
    }

    /**
     * response formatting:
     */
    function getSellerPaymentStatus()
    external
    view
    returns (address[] memory, uint256[] memory, uint256[] memory)
    {
        uint256 totalLength = feeTokens.length + 1;
        address[] memory spendingTokens = new address[](totalLength);
        uint256[] memory expectedAmounts = new uint[](totalLength);
        uint256[] memory paidAmounts = new uint[](totalLength);
        uint256 feeTokensLength = feeTokens.length;
        for (uint256 i = 0; i < feeTokensLength; i++) {
            spendingTokens[i] = feeTokens[i];
            expectedAmounts[i] = tokenFeeAmounts[seller][feeTokens[i]];
            paidAmounts[i] = paidTokenFeeAmounts[seller][feeTokens[i]];
        }

        spendingTokens[feeTokens.length] = address(registry.getCollateralManagementToken());

        expectedAmounts[feeTokens.length] = sellerPayment.amount;

        paidAmounts[feeTokens.length] = sellerPayment.paidAmount;

        return (spendingTokens, expectedAmounts, paidAmounts);
    }

    /**
     * response formatting:
     */
/*
    function getBuyerPaymentStatus()
    external
    view
    returns (address[] memory, uint256[] memory, uint256[] memory)
    {
        address[] memory spendingTokens;
        uint256[] memory expectedAmounts;
        uint256[] memory paidAmounts;

        (spendingTokens, expectedAmounts, paidAmounts) = feePaymentStatus(
            buyer
        );

        uint256 tokenFeesLength = spendingTokens.length;
        if (tokenFeesLength == 0) {
            spendingTokens = new address[](1);
            expectedAmounts = new uint256[](1);
            paidAmounts = new uint256[](1);

            spendingTokens[0] = address(buyerPayment.token);
            expectedAmounts[0] = buyerPayment.amount;
            paidAmounts[0] = buyerPayment.paidAmount;
        } else {
            bool isFiatTokenInList = false;
            for (uint256 i = 0; i < tokenFeesLength; i++) {
                // if trading fiat token is including in list
                if (
                    spendingTokens[i] == address(buyerPayment.token)
                ) {
                    expectedAmounts[i] = expectedAmounts[i].add(
                        buyerPayment.amount
                    );
                    paidAmounts[i] = paidAmounts[i].add(
                        buyerPayment.paidAmount
                    );
                    isFiatTokenInList = true;
                }
            }
            // If fiat token is not in list, append it to list
            if (!isFiatTokenInList) {
                spendingTokens.push(address(buyerPayment.token));
                expectedAmounts.push(buyerPayment.amount);
                paidAmounts.push(buyerPayment.paidAmount);
            }
        }

        return (spendingTokens, expectedAmounts, paidAmounts);
    }
*/

    function getTradeInfo()
    public
    view
    returns (
        address _seller,
        address _buyer,
        address _buyerPaymentTokenAddress,
        uint256 _buyerPaymentAmount,
        uint256 _buyerPaidAmount,
        uint256 _sellerPaymentTokenIndex,
        uint256 _sellerPaymentAmount,
        uint256 _sellerPaidAmount
    )
    {
        _seller = seller;
        _buyer = buyer;
        _buyerPaymentTokenAddress = address(buyerPayment.token);
        _buyerPaymentAmount = buyerPayment.amount;
        _buyerPaidAmount = buyerPayment.paidAmount;
        _sellerPaymentTokenIndex = sellerPayment.tokenIndex;
        _sellerPaymentAmount = sellerPayment.amount;
        _sellerPaidAmount = sellerPayment.paidAmount;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

}