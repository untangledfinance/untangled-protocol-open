// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AssetsTransformation.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract TokenTopup is AssetsTransformation {

    constructor(
        address _creator,
        string memory _refID,
        address _owner,
        uint8 _tokenType,
        address _tokenAddress,
        uint _amount,
        uint _expTime
    ) AssetsTransformation(
        _creator,
        _refID,
        _owner,
        _tokenType,
        _tokenAddress,
        _amount,
        _expTime
    ) {
    }

    event TopupCompleted(address indexed tokenOwner, uint amount, uint time);
    event TopupCanceled(address indexed tokenOwner, uint amount, uint time);


    // ============================ //
    // Expiration time functions
    // ============================ //
    function submitExpirationRelease() public onlyCreator {
        require(tokenType != TokenType.Unknown, "TokenTopup: Token type is not specified.");
        require(isCompletedFeesPayment(), "TokenTopup: Fee payment is not completed yet.");
        require(_inState(State.Expired) || isExpired(), "TokenTopup: This function only for expired smart contract.");
        _topupTermination();
        state = State.Expired;
        emit ExpirationRelease(address(this), block.timestamp);
    }

    function cancel() public onlyCreator returns (bool) {
        require(tokenType != TokenType.Unknown, "TokenTopup: Token type is not specified.");
        require(isCompletedFeesPayment(), "TokenTopup: Fee payment is not completed yet.");
        require(_notInState(State.Completed), "TokenTopup: Not allowed for completed Topup.");
        _topupTermination();
        state = State.Canceled;
        emit TopupCanceled(tokenOwner, amount, block.timestamp);
        return true;
    }

    function complete() public onlyCreator returns (bool) {
        require(tokenType != TokenType.Unknown, "TokenTopup: Token type is not specified.");
        require(isCompletedFeesPayment(), "TokenTopup: Fee payment is not completed yet.");
        require(
            _notInState(State.Expired) && _notInState(State.Canceled) && _notInState(State.Completed),
            "TokenTopup: Not allowed for expired or canceled/completed Topup."
        );
        _releaseTopup();
        state = State.Completed;
        emit TopupCompleted(tokenOwner, amount, block.timestamp);
        return true;
    }


    // ============================ //
    // INTERNAL functions
    // ============================ //
    function _topupTermination() internal {
        ERC20Burnable(tokenAddress).burn(amount);
        _releaseFees();
    }

    function _releaseTopup() internal {
        ERC20Burnable(tokenAddress).transfer(tokenOwner, amount);
        _releaseFees();
    }
}
