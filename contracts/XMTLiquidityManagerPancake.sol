// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "./AdminRoleUpgrade.sol";
import "./libraries/CSTDateTime.sol";

interface IPancakeRouter02 {

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function addLiquidity(

        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
}

interface IPancakePair {

    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}
interface IERC20 {

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function decimals() external view returns (uint8);
}
contract XMTLiquidityManagerPancake  is AdminRoleUpgrade, Initializable {

    using CSTDateTime for *;

    IERC20 public  uToken;
    IERC20 public  token;
    IPancakeRouter02 public  router;
    IPancakePair public  pool;
    bool public isOpenVirtualPrice;
    uint256 public baseXmtPrice;
    mapping(uint256 => uint256) public basePriceHistory;

    event LiquidityAdded(uint256 uUsed, uint256 tokenUsed, uint256 liquidityMinted);

    function initialize() public initializer {
        _addAdmin(msg.sender);
        baseXmtPrice = 10**18;
    }

    function setAboutAddress(address _uToken, address _token, address _router, address _pool) external onlyAdmin {
        require(_uToken != address(0) && _token != address(0) && _router != address(0) && _pool != address(0), "zero addr");
        uToken = IERC20(_uToken);
        token = IERC20(_token);
        router = IPancakeRouter02(_router);
        pool = IPancakePair(_pool);
    }

    function setBasePrice(uint256 _basePrice18) external onlyAdmin {
        require(_basePrice18 > 0, "basePrice18=0");
        baseXmtPrice = _basePrice18;
    }

    function setIsOpenVirtualPrice(bool _isOpenVirtualPrice) external onlyAdmin {
        isOpenVirtualPrice = _isOpenVirtualPrice;
    }

    function updateBasePrice(int256 rate) external onlyAdmin {
        if(rate <= 0){
            rate = 0;
        }

        int256 newPrice = int256(baseXmtPrice) * (int256(1_000_000) + rate) / int256(1_000_000);
        if (newPrice < 0) {
            newPrice = 0;
        }
        baseXmtPrice = uint256(newPrice);
        basePriceHistory[CSTDateTime.today()] = baseXmtPrice;
    }

    function getTokenPriceInU() external view returns (uint256 price18) {
        if(isOpenVirtualPrice){
            return baseXmtPrice;
        }

        address t0 = pool.token0();
        (uint256 r0, uint256 r1, ) = pool.getReserves();
        uint8 decU = uToken.decimals();
        uint8 decT = token.decimals();
        if (address(token) == t0) {
            price18 = _priceScaled(r1, r0, decT, decU);
        } else {
            price18 = _priceScaled(r0, r1, decT, decU);
        }
    }

    function buyTokenWithU(uint256 uAmountIn, uint256 minTokenOut, address to) external  onlyAdmin returns (uint256[] memory amounts) {
        require(uAmountIn > 0, "u=0");
        require(to != address(0), "to=0");
        require(uToken.transferFrom(msg.sender, address(this), uAmountIn), "transfer U failed");
        require(uToken.approve(address(router), 0), "approve reset U failed");
        require(uToken.approve(address(router), uAmountIn), "approve U failed");
        address[] memory path = new address[](2);
        path[0] = address(uToken);
        path[1] = address(token);
        amounts = router.swapExactTokensForTokens(uAmountIn, minTokenOut, path, to, block.timestamp);
    }

    function buyUWithToken(uint256 tokenAmountIn, uint256 minUOut, address to) external onlyAdmin returns (uint256[] memory amounts) {
        require(tokenAmountIn > 0, "t=0");
        require(to != address(0), "to=0");
        require(token.transferFrom(msg.sender, address(this), tokenAmountIn), "transfer T failed");
        require(token.approve(address(router), 0), "approve reset T failed");
        require(token.approve(address(router), tokenAmountIn), "approve T failed");
        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = address(uToken);
        amounts = router.swapExactTokensForTokens(tokenAmountIn, minUOut, path, to, block.timestamp);
    }

    function _priceScaled(uint256 reserveU, uint256 reserveT, uint8 decT, uint8 decU) internal pure returns (uint256) {
        require(reserveT > 0, "no token reserve");
        uint256 scale;
        unchecked {
            if (decT >= decU) {
                scale = 10 ** (uint256(18) + (decT - decU));
                return reserveU * scale / reserveT;
            } else {
                scale = 10 ** 18;
                uint256 down = 10 ** (decU - decT);
                return reserveU * (scale / down) / reserveT;
            }
        }
    }

    function addLiquidityWithU(uint256 uAmountIn, address to) external onlyAdmin returns (uint256 liquidityMinted) {
        require(uAmountIn > 0, "u=0");
        require(to != address(0), "to=0");
        require(uToken.balanceOf(address(this)) >= uAmountIn, "insufficient U");
        uint256 uForSwap = uAmountIn / 2;
        uint256 uForLP = uAmountIn - uForSwap;
        require(uToken.approve(address(router), 0), "approve reset U failed");
        require(uToken.approve(address(router), uForSwap), "approve U failed");
        {
            uint256 beforeBal = token.balanceOf(address(this));
            address[] memory path = new address[](2);
            path[0] = address(uToken);
            path[1] = address(token);
            router.swapExactTokensForTokens(uForSwap, 0, path, address(this), block.timestamp);
            uint256 afterBal = token.balanceOf(address(this));
            require(afterBal > beforeBal, "swap failed");
        }

        uint256 tokenForLP = token.balanceOf(address(this));
        require(uToken.approve(address(router), 0), "approve reset U2 failed");
        require(uToken.approve(address(router), uForLP), "approve U2 failed");
        require(token.approve(address(router), 0), "approve reset T failed");
        require(token.approve(address(router), tokenForLP), "approve T failed");
        ( , , liquidityMinted) = router.addLiquidity(
            address(token),
            address(uToken),
            tokenForLP,
            uForLP,
            0,
            0,
            to,
            block.timestamp
        );
        emit LiquidityAdded(uForLP, tokenForLP, liquidityMinted);
    }

    function addLiquidityFromCaller(uint256 uAmountIn, uint256 maxTokenAmount, address to)
        external
        onlyAdmin
        returns (uint256 liquidityMinted, uint256 uUsed, uint256 tokenUsed)
    {
        require(maxTokenAmount > 0, "t=0");
        require(to != address(0), "to=0");
        require(uAmountIn > 0, "u=0");
        (uint256 r0, uint256 r1, ) = pool.getReserves();
        address t0 = pool.token0();
        bool tokenIs0 = (address(token) == t0);
        uint256 needToken = tokenIs0 ? (uAmountIn * r0 / r1) : (uAmountIn * r1 / r0);
        if (needToken > maxTokenAmount) {
            tokenUsed = maxTokenAmount;
            uUsed = tokenIs0 ? (tokenUsed * r1 / r0) : (tokenUsed * r0 / r1);
        } else {
            tokenUsed = needToken;
            uUsed = uAmountIn;
        }
        require(token.balanceOf(address(this)) >= tokenUsed, "insufficient T");
        require(uToken.transferFrom(msg.sender, address(this), uUsed), "pull U failed");
        require(uToken.approve(address(router), 0), "approve reset U failed");
        require(uToken.approve(address(router), uUsed), "approve U failed");
        require(token.approve(address(router), 0), "approve reset T failed");
        require(token.approve(address(router), tokenUsed), "approve T failed");
        ( , , liquidityMinted) = router.addLiquidity(
            address(token),
            address(uToken),
            tokenUsed,
            uUsed,
            0,
            0,
            to,
            block.timestamp
        );
        emit LiquidityAdded(uUsed, tokenUsed, liquidityMinted);
        require(tokenUsed <= maxTokenAmount, "token used overflow");
        uint256 leftover = maxTokenAmount - tokenUsed;
        if (leftover > 0) {
            require(token.transfer(msg.sender, leftover), "refund T failed");
        }
    }
}