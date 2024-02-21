//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BadExchange is ERC20 {
    using SafeERC20 for IERC20;

    IERC20 private immutable i_wethToken;
    IERC20 private immutable i_poolToken;

    // Takes in two tokens which are going to offer out lptokens for liquidators
    constructor(
        address poolToken,
        address wethToken,
        string memory liquidityTokenName,
        string memory liquidityTokenSymbol
    ) ERC20(liquidityTokenName, liquidityTokenSymbol) {
        i_wethToken = IERC20(wethToken);
        i_poolToken = IERC20(poolToken);
    }

    //add liquidity and mints lptokens to the liquidityprovidiers.abi
    //lptokens will represent the shares of the pools provided, providing is binary not singular
    function deposit(
        uint256 wethToDeposit,
        uint256 maximumPoolTokensToDeposit
    ) external returns (uint256 liquidityTokensToMint) {
        if (totalLiquidityTokenSupply() > 0) {
            uint256 wethReserves = i_wethToken.balanceOf(address(this));
            uint256 poolTokensToDeposit = getPoolTokensToDepositBasedOnWeth(
                wethToDeposit
            );
            liquidityTokensToMint =
                (wethToDeposit * totalLiquidityTokenSupply()) /
                wethReserves;
            _addLiquiditMintAndTransfer(
                wethToDeposit,
                poolTokensToDeposit,
                liquidityTokensToMint
            );
        } else {
            _addLiquiditMintAndTransfer(
                wethToDeposit,
                maximumPoolTokensToDeposit,
                wethToDeposit
            );
            liquidityTokensToMint = wethToDeposit;
        }
    }

    // does the opposite of deposit
    // it burns lptokens and calculates how much weth and pooltoken to remove from its pool and sends it back to the liquidity provider
    function withdraw(uint256 liquidityTokensToBurn) external {
        uint256 wethToWithdraw = (liquidityTokensToBurn *
            i_wethToken.balanceOf(address(this))) / totalLiquidityTokenSupply();
        uint256 poolTokensToWithdraw = (liquidityTokensToBurn *
            i_poolToken.balanceOf(address(this))) / totalLiquidityTokenSupply();
        _burn(msg.sender, liquidityTokensToBurn);
        i_wethToken.safeTransfer(msg.sender, wethToWithdraw);
        i_poolToken.safeTransfer(msg.sender, poolTokensToWithdraw);
    }

    //one of the most important function it calculates how much tokena will be swappped for tokenb - fee and returns the amount of tokenb
    function getOutputAmountBasedOnInput(
        uint256 inputAmount,
        uint256 inputReserves,
        uint256 outputReserves
    ) public pure returns (uint256 outputAmount) {
        uint256 inputAmountMinusFee = inputAmount * 1000;
        uint256 numerator = inputAmountMinusFee * outputReserves;
        uint256 denominator = (inputReserves * 1000) + inputAmountMinusFee;
        return numerator / denominator;
    }

    // does the opposite of the above checks how much you should pay to acquire tokenb for tokena
    // a bug is here not minus fee
    function getInputAmountBasedOnOutput(
        uint256 outputAmount,
        uint256 inputReserves,
        uint256 outputReserves
    ) public pure returns (uint256 inputAmount) {
        return
            ((inputReserves * outputAmount) * 1000) /
            ((outputReserves - outputAmount) * 1000);
    }

    // uses getoutputAmountBasedOnInput to get how many tokens willl be released for
    // @param inputAmount calls the _swap function
    function swapExactInput(
        IERC20 inputToken,
        uint256 inputAmount,
        IERC20 outputToken
    ) public {
        uint256 inputReserves = inputToken.balanceOf(address(this));
        uint256 outputReserves = outputToken.balanceOf(address(this));
        uint256 outputAmount = getOutputAmountBasedOnInput(
            inputAmount,
            inputReserves,
            outputReserves
        );
        _swap(inputToken, inputAmount, outputToken, outputAmount);
    }

    function swapExactOutput(
        IERC20 inputToken,
        IERC20 outputToken,
        uint256 outputAmount
    ) public returns (uint256 inputAmount) {
        uint256 inputReserves = inputToken.balanceOf(address(this));
        uint256 outputReserves = outputToken.balanceOf(address(this));

        inputAmount = getInputAmountBasedOnOutput(
            outputAmount,
            inputReserves,
            outputReserves
        );
        _swap(inputToken, inputAmount, outputToken, outputAmount);
    }

    function _addLiquiditMintAndTransfer(
        uint256 wethToDeposit,
        uint256 poolTokensToDeposit,
        uint256 liquidityTokensToMint
    ) private {
        _mint(msg.sender, liquidityTokensToMint);
        i_wethToken.safeTransferFrom(msg.sender, address(this), wethToDeposit);
        i_poolToken.safeTransferFrom(
            msg.sender,
            address(this),
            poolTokensToDeposit
        );
    }

    function _swap(
        IERC20 inputToken,
        uint256 inputAmount,
        IERC20 outputToken,
        uint256 outputAmount
    ) private {
        inputToken.safeTransferFrom(msg.sender, address(this), inputAmount);
        outputToken.safeTransfer(msg.sender, outputAmount);
    }

    function getPoolTokensToDepositBasedOnWeth(
        uint256 wethToDeposit
    ) public view returns (uint256) {
        uint256 poolTokenReserves = i_poolToken.balanceOf(address(this));
        uint256 wethReserves = i_wethToken.balanceOf(address(this));
        return (wethToDeposit * poolTokenReserves) / wethReserves;
        //
    }

    function totalLiquidityTokenSupply() public view returns (uint256) {
        return totalSupply();
    }

    function getPoolToken() external view returns (address) {
        return address(i_poolToken);
    }

    function getWeth() external view returns (address) {
        return address(i_wethToken);
    }

    function getPriceOfOneWethInUSDC() external view returns (uint256) {
        return
            getOutputAmountBasedOnInput(
                1e18,
                i_wethToken.balanceOf(address(this)),
                i_poolToken.balanceOf(address(this))
            );
    }

    function getPriceOfUSDCInWeth() external view returns (uint256) {
        return
            getOutputAmountBasedOnInput(
                1e18,
                i_poolToken.balanceOf(address(this)),
                i_wethToken.balanceOf(address(this))
            );
    }
}
