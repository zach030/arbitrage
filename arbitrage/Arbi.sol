// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.0;

// 借贷接口
interface ILiquidity {
    function borrow(address _token, uint256 _amount, bytes calldata _data) external;
}

// -- interface -- //
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
}

contract Arbi {
    address owner; // owner
    address liquidityPool = 0x4F868C1aa37fCf307ab38D215382e88FCA6275E2;
    address borrowerProxy = 0x17a4C8F43cB407dD21f9885c5289E66E21bEcD9D;
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    struct RepayData {
        address repay_token;
        uint256 repay_amount;
    }
    constructor() {
        owner = address(tx.origin);
    }

    modifier onlyOwner {
        require(address(msg.sender)==owner,"No authority")
        _;
    }

    receive() external payable{}

    // 执行闪电贷，借款token，数额amount
    function flashLoan(address token, uint256 amount) public onlyOwner {
        RepayData memory _repay_data = RepayData(token,amount);
        // 从liquidity中借出token，注册回调函数
        ILiquidity(liquidityPool).borrow(token,amount,abi.encodeWithSelector(this.receiveLoan.selector, abi.encode(_repay_data)));
    }

    // 接收贷款后的回调函数
    function receiveLoan(bytes memory data) public{
        require(msg.sender==borrowerProxy, "Not borrower");
        // 这时已经收到借款，在这里执行逻辑，最后还款
        RepayData memory _repay_data = abi.decode(data,(RepayData));
        IERC20(_repay_data.repay_token).transfer(liquidityPool,_repay_data.repay_amount);
    }
}