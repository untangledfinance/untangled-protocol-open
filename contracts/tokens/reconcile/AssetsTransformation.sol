// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract AssetsTransformation {
    using SafeMath for uint256;

    address internal creator;
    address internal tokenOwner;
    address internal tokenAddress;

    string internal referenceID;

    uint internal amount;
    uint internal createdTime;
    uint internal expirationTime;

    //********** Setting up fees *************/
    struct TransformationFees {
        uint256 amount;
        address token;
        address beneficiary;
    }

    mapping(address => bool) isFeeTokens;
    address[] feeTokens;

    // fee type id => fee details list)
    // For now only support 1 beneficiary for 1 type of fee from each payers
    mapping(bytes32 => TransformationFees) requiredFees;
    mapping(bytes32 => bool) isRequiredFeeTypes;
    bytes32[] requiredFeeTypeIds;

    // Fee token => map to required amount
    mapping(address => uint256) tokenFeeAmounts;
    // Fee token => map to paid amount
    mapping(address => uint256) paidTokenFeeAmounts;
    mapping(address => uint256) releasedTokenFeeAmounts;
    //****************************************/

    event ContractExpired(address indexed contractAddress, uint time);
    event ExpirationRelease(address indexed contractAddress, uint time);

    event SetupNewFee(address indexed _beneficiary, uint256 _amount, address _token);
    event NewFeePayment(address indexed _payer, uint256 _amount, address _token);
    event NewFeeReleased(address indexed _beneficiary, uint _amount, address indexed _token);

    event AddedNewFeeType(bytes32 indexed _id);

    enum State { Proposed, Completed, Expired, Canceled}
    enum TokenType { Unknown, Commodity, Fiat }

    State state;
    TokenType internal tokenType;

    modifier onlyCreator {
        require(msg.sender == creator, "AssetsTransformation: Sender must be creator of smart contract instance.");
        _;
    }

    modifier onlyTokenOwner {
        require(msg.sender == tokenOwner, "AssetsTransformation: Sender must be token owner.");
        _;
    }
    constructor(
        address _creator,
        string memory _refID,
        address _owner,
        uint8 _tokenType,
        address _tokenAddress,
        uint _amount,
        uint _expTime
    ) {
        creator = _creator;
        referenceID = _refID;
        tokenAddress = _tokenAddress;
        amount = _amount;
        tokenOwner = _owner;
        expirationTime = _expTime;
        if (_tokenType == uint8(TokenType.Commodity)) {
            tokenType = TokenType.Commodity;
        } else if(_tokenType == uint8(TokenType.Fiat)) {
            tokenType = TokenType.Fiat;
        } else {
            tokenType = TokenType.Unknown;
        }

        // solium-disable-next-line
        createdTime = block.timestamp;
        state = State.Proposed;
    }

    /********* INTERNAL FUNCS *********/

    function _transferTokensFrom(
        address _token,
        address _from,
        address _to,
        uint256 _amount
    ) internal returns (bool success) {
        return
            IERC20(_token).transferFrom(
                _from,
                _to,
                _amount
            );
    }

    // Transfer fee to beneficiary
    function _transferFeeToBeneficiary(
        uint256 _amount,
        address _token,
        address _beneficiary
    ) internal {
//        BinkabiERC20Token tokenInstance = BinkabiERC20Token(_token);
/*
        require(
            tokenInstance.approve(tokenTransferProxy, _amount),
            "Fees: Unable to grant permission for transferring token to proxy."
        );
*/
        require(
            _transferTokensFrom(_token, address(this), _beneficiary, _amount),
            "Fees: Unable to transfer fee to beneficiary."
        );
        _newFeeReleaseHasCompleted(_beneficiary, _amount, _token);
    }

    // Add token fee to list if it is non-existed
    function _addFeeToken(address token) internal {
        if (!isFeeTokens[token]) {
            feeTokens.push(token);
            isFeeTokens[token] = true;
        }
    }

    function _addFeeTypeId(uint256 id) internal {
        if (!isRequiredFeeTypes[bytes32(id)]) {
            requiredFeeTypeIds.push(bytes32(id));
            isRequiredFeeTypes[bytes32(id)] = true;
            emit AddedNewFeeType(bytes32(id));
        }
    }

    // Add fee amount to respective existing fee token
    function _setupNewFeePayment(
        uint256 _amount,
        address _token
    ) internal {
        uint256 totalRequiredAmount = tokenFeeAmounts[_token].add(
            _amount
        );
        tokenFeeAmounts[_token] = totalRequiredAmount;
    }

    // Setup new fee for this exchange, new fee type/amount/beneficiary
    function _setupFee(
        uint256 _feeId,
        uint256 _amount,
        address _token,
        address _beneficiary
    ) internal {
        TransformationFees memory fee = TransformationFees({
            amount: _amount,
            token: _token,
            beneficiary: _beneficiary
        });
        requiredFees[bytes32(_feeId)] = fee;
        _addFeeToken(_token);
        _addFeeTypeId(_feeId);
        _setupNewFeePayment(_amount, _token);
        emit SetupNewFee(_beneficiary, _amount, _token);
    }

    // Whenever there is new fee payment to this withdrawal/top-up
    function _newFeePaymentHasCompleted(
        address _payer,
        uint256 _amount,
        address _token
    ) internal {
        uint256 totalPaid = paidTokenFeeAmounts[_token].add(_amount);
        paidTokenFeeAmounts[_token] = totalPaid;
        emit NewFeePayment(_payer, _amount, _token);
    }

    function _newFeeReleaseHasCompleted(
        address _beneficiary,
        uint256 _amount,
        address _token
    ) internal {
        uint256 totalReleased = releasedTokenFeeAmounts[_token].add(_amount);
        releasedTokenFeeAmounts[_token] = totalReleased;
        emit NewFeeReleased(_beneficiary, _amount, _token);
    }


    function _isCompletedFeePaymentWithToken(address _token)
        internal
        view
        returns (bool)
    {
        return paidTokenFeeAmounts[_token] >= tokenFeeAmounts[_token];
    }

    // Release fees to respective beneficiary
    function _releaseFees() internal {
        uint256 feeTypesLength = requiredFeeTypeIds.length;
        if (feeTypesLength > 0) {
            for (uint256 i = 0; i < feeTypesLength; i++) {
                TransformationFees memory fee = requiredFees[requiredFeeTypeIds[i]];
                if (paidTokenFeeAmounts[fee.token] > releasedTokenFeeAmounts[fee.token]) {
                    uint256 remain = paidTokenFeeAmounts[fee.token].sub(releasedTokenFeeAmounts[fee.token]);
                    if (remain >= fee.amount) {
                        _transferFeeToBeneficiary(
                            fee.amount,
                            fee.token,
                            fee.beneficiary
                        );
                    } else {
                        _transferFeeToBeneficiary(
                            remain,
                            fee.token,
                            fee.beneficiary
                        );
                    }
                }
            }
        }
    }

    /****** State functions ******/
    function _inState(State _state) internal view returns (bool) {
        return (state == _state);
    }

    function _notInState(State _state) internal view returns (bool) {
        return (state != _state);
    }

    // ============================ //
    // Fee functions
    // ============================ //

    function payFee(uint256 _amount, address _token) public onlyTokenOwner {
        if (_transferTokensFrom(_token, msg.sender, address(this), _amount)) {
            _newFeePaymentHasCompleted(msg.sender, _amount, _token);
        }
    }

    function setupFee(uint256 _feeId, uint256 _amount, address _token, address _beneficiary) public {
        require(_feeId > 0, "AssetsTransformation: Invalid fee Id.");
        require(_amount > 0, "AssetsTransformation: Invalid fee amount.");
        require(_beneficiary != address(0x0), "AssetsTransformation: Invalid beneficiary of fee.");
        _setupFee(_feeId, _amount, _token, _beneficiary);
    }

    // Query current status of fees payment
    function feePaymentStatus()
        public
        view
        returns (address[] memory, uint256[] memory, uint256[] memory)
    {
        uint256 feeTokensLength = feeTokens.length;
        uint256[] memory expectedAmounts = new uint256[](feeTokensLength);
        uint256[] memory paidAmounts = new uint256[](feeTokensLength);

        for (uint256 i = 0; i < feeTokensLength; i++) {
            expectedAmounts[i] = tokenFeeAmounts[feeTokens[i]];
            paidAmounts[i] = paidTokenFeeAmounts[feeTokens[i]];
        }

        return (feeTokens, expectedAmounts, paidAmounts);
    }


    function isCompletedFeesPayment()
        public
        view
        returns (bool)
    {
        // default is true. Because, assume that there is no token fee -> user don't need to pay for any fee
        bool isCompleted = true;
        uint256 feeTokensLength = feeTokens.length;
        if (feeTokensLength > 0) {
            for (uint256 i = 0; i < feeTokensLength; i++) {
                if (!_isCompletedFeePaymentWithToken(feeTokens[i])) {
                    isCompleted = false;
                    break;
                }
            }
        }
        return isCompleted;
    }

    // ============================ //
    // Timing functions
    // ============================ //
    function getExpirationTime() public view returns (uint) {
        return expirationTime;
    }

    function getCreatedTime() public view returns (uint) {
        return createdTime;
    }

    function getState() public view returns (uint8) {
        return uint8(state);
    }

    function validateExpirationTime() public returns (bool) {
        // solium-disable-next-line
        if (block.timestamp.sub(createdTime) >= expirationTime) {
            state = State.Expired;
            // solium-disable-next-line
            emit ContractExpired(address(this), block.timestamp);
            return true;
        } else {
            return false;
        }
    }

    function expirationTimeLeft() public view returns (uint) {
        // solium-disable-next-line
        uint elapseTime = block.timestamp.sub(createdTime);
        if (expirationTime > elapseTime) {
            return expirationTime.sub(elapseTime);
        } else {
            return 0;
        }
    }
    /**
     */
    function setExpirationTime(uint duration) public  onlyCreator {
        expirationTime = duration;
    }


    function isExpired() public view returns (bool) {
        // solium-disable-next-line
        if (expirationTime > block.timestamp.sub(createdTime)) {
            return false;
        } else {
            return true;
        }
    }


    /****************************/
    // EXTERNAL FUNCS
    /****************************/

    /** CALL **/
    function getBeneficiaryByFeeId(uint256 _feeId) public view returns (address) {
        return requiredFees[bytes32(_feeId)].beneficiary;
    }
}
