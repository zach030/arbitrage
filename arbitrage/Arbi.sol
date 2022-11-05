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

// Curve 池子接口
interface ICurveCrypto {
    function exchange(uint256 from, uint256 to, uint256 from_amount, uint256 min_to_amount) external payable;
    function get_dy(uint256 from, uint256 to, uint256 from_amount) external view returns(uint256);
}

// uniswap pair 接口
interface IUniswapV3Pair {
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);
    function fee() external view returns(uint24);
}

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        return c;
    }
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

library SafeERC20 {
    using SafeMath for uint256;
    using Address for address;

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).add(value);
        callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).sub(value, "SafeERC20: decreased allowance below zero");
        callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }
    function callOptionalReturn(IERC20 token, bytes memory data) private {
        require(address(token).isContract(), "SafeERC20: call to non-contract");
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "SafeERC20: low-level call failed");
        if (returndata.length > 0) {
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

library TickMath {
    /// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;
}

contract Arbi {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    address owner; // owner
    address liquidityPool = 0x4F868C1aa37fCf307ab38D215382e88FCA6275E2;
    address borrowerProxy = 0x17a4C8F43cB407dD21f9885c5289E66E21bEcD9D;
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    struct RepayData {
        address repay_token;
        uint256 repay_amount;
        address recipient;
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

    function ApproveToken(address token, address spender, uint256 amount)  internal{
        uint256 allowance = IERC20(token).allowance(address(this),spender);
        if (allowance<amount){
            // Beware that changing an allowance with this method brings the risk that someone may use both the old and the new allowance by unfortunate transaction ordering. 
            // One possible solution to mitigate this race condition is to first reduce the spender’s allowance to 0 and set the desired value afterwards
            // https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
            IERC20(token).safeApprove(spender,0);
            IERC20(token).safeApprove(spender,MAX_INT);
        }
    }

    function CurveCryptoExchange(address pool, uint256 token_in_id, uint256 token_out_id, address token_in, uint256 amount_in) internal  {
        ApproveToken(token_in, pool, amount_in);
        ICurveCrypto(pool).exchange(token_in_id, token_out_id, amount_in, 0);
    }

    function UniswapV3Swap(address pool, address token_in, address token_out, uint256 amount_in) internal {
        bool zeroForOne = token_in < token_out;
        RepayData memory repay_data = RepayData(token_in,amount_in,pool);
        IUniswapV3Pair(pool).swap(address(this),zeroForOne, int256(amount_in)),
         (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1), abi.encode(repay_data));
    }
}