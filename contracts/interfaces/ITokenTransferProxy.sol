pragma solidity ^0.8.0;

/**
 * The TokenTransferProxy is a proxy contract for transfering principal
 * and fee payments and repayments between agents and keepers in the Untangled
 * ecosystem.  It is decoupled from the CommodityDebtKernel in order to make upgrades to the
 * protocol contracts smoother -- if the CommodityDebtKernel or RepaymentRouter is upgraded to a new contract,
 * creditors will not have to grant new transfer approvals to a new contract's address.
 */
interface ITokenTransferProxy {
    //=-------------------------
    // EXT: SEND
    //=-------------------------
    /**
     * Transfer specified token amount from _from address to _to address on give token
     */
    function transferFrom(
        address _token,
        address _from,
        address _to,
        uint256 _amount
    ) public virtual returns (bool _success);

    /**
     * Batch transfer specified token amount from _from address to _to address on give token
     */
    function batchTransferFrom(
        address[] calldata _tokens,
        address[] calldata _froms,
        address[] calldata _toes,
        uint256[] calldata _amounts
    ) external virtual;

}
