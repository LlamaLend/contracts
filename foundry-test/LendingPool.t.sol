// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "../contracts/LendingPool.sol";
import "../contracts/LlamaLendFactory.sol";
import "../contracts/mocks/MockNFT.sol";
import "./utils/SigUtils.sol";

contract LendingPoolTest is Test {
    uint216 constant ONE_ETH = 1 ether;
    uint216 constant ONE_TENTH_OF_AN_ETH = 0.1 ether;
    uint216 constant TWO_TENTHS_OF_AN_ETH = 0.2 ether;

    uint256 constant startMaxDailyBorrows = ONE_ETH;
    uint256 constant SECONDS_PER_DAY = 24 * 60 * 60;
    uint256 constant DAYS_PER_YEAR = 365;
    uint256 constant SECONDS_PER_YEAR = DAYS_PER_YEAR * SECONDS_PER_DAY;
    uint256 constant INTEREST_WEI_PER_ETH_PER_YEAR = 0.8 ether; // 0.8e18
    uint256 constant MAX_INTEREST = 0.7 ether; // 0.7e18
    uint256 DEADLINE;
    uint256 constant MINIMUM_INTEREST = 12683916793; // 40%
    uint256 constant LTV = 0.5 ether; // 0.5e18 (50%)
    uint216 constant PRICE = TWO_TENTHS_OF_AN_ETH;
    uint256 constant MAX_LOAN_LENGTH = 14 * SECONDS_PER_DAY; // 2 weeks

    address owner = vm.addr(0x01);
    uint256 oraclePrivateKey = 0x02;
    address oracle = vm.addr(oraclePrivateKey);
    address liquidator = vm.addr(0x03);
    address user = vm.addr(0x04);

    LlamaLendFactory factory;
    LendingPool lendingPool;
    LendingPool.Interests interests;
    MockNFT nft;
    uint256 chainId;
    SigUtils sigUtils;

    function setUp() public {
        DEADLINE = (block.timestamp / 1000) + 1000;
        chainId = block.chainid;
        sigUtils = new SigUtils();

        vm.startPrank(owner);
        LendingPool lendingPoolImplementation = new LendingPool();
        factory = new LlamaLendFactory(lendingPoolImplementation);
        interests = LendingPool.Interests(
            INTEREST_WEI_PER_ETH_PER_YEAR / SECONDS_PER_YEAR,
            MINIMUM_INTEREST,
            LTV
        );
        nft = new MockNFT();
        lendingPool = factory.createPool(
            oracle,
            ONE_TENTH_OF_AN_ETH,
            address(nft),
            startMaxDailyBorrows,
            "TubbyLoan",
            "TL",
            uint96(MAX_LOAN_LENGTH),
            interests
        );
        lendingPool.setMaxPrice(ONE_ETH); // 1eth
        vm.stopPrank();

        nft.mint(10, user);

        vm.deal(owner, 1000 ether); // seed ether balance
        vm.deal(user, 1000 ether); // seed ether balance
    }

    function test_Initialization() public {
        assertEq(nft.ownerOf(1), user);
    }

    function testRevert_InitializeTwice() public {
        vm.expectRevert("Initializable: contract is already initialized");
        lendingPool.initialize(
            oracle,
            ONE_TENTH_OF_AN_ETH,
            startMaxDailyBorrows,
            "TubbyLoan",
            "TL",
            interests,
            user,
            address(nft),
            address(factory),
            uint96(SECONDS_PER_DAY)
        );
    }

    function test_PriceOracleSignature() public {
        (uint8 v, bytes32 r, bytes32 s) = _generateSignature();

        vm.prank(owner);
        lendingPool.setMaxPrice(ONE_ETH); // 1eth
        lendingPool.checkOracle(PRICE, DEADLINE, v, r, s);
    }

    function testRevert_ExpiredPriceOracleSignature() public {
        (uint8 v, bytes32 r, bytes32 s) = _generateSignature();

        vm.warp(block.timestamp + 1000 + 1);

        vm.expectRevert("deadline over");
        lendingPool.checkOracle(PRICE, DEADLINE, v, r, s);
    }

    function test_CurrentAnnualInterestWhenZeroEthInContract() public {
        assertEq(
            lendingPool.currentAnnualInterest(0),
            MINIMUM_INTEREST * SECONDS_PER_YEAR
        );
    }

    function test_DepositByOwner() public {
        vm.prank(owner);
        lendingPool.deposit{value: ONE_ETH}();
        assertEq(address(lendingPool).balance, ONE_ETH);
    }

    function testRevert_DepositByNonOwner() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        lendingPool.deposit{value: ONE_ETH}();
    }

    function test_AddLiquidatorByOwner() public {
        vm.prank(owner);
        lendingPool.addLiquidator(liquidator);
        assertEq(lendingPool.liquidators(liquidator), true);
    }

    function testRevert_AddLiquidatorByNonOwner() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        lendingPool.addLiquidator(liquidator);
    }

    function testRevert_userBorrowNftsWithNftsNotOwnedByCaller() public {
        _ownerDepositIntoLendingPool();

        (uint8 v, bytes32 r, bytes32 s) = _generateSignature();
        uint256[] memory nftIds = new uint256[](2);
        nftIds[0] = 0;
        nftIds[1] = 1;

        vm.prank(user);
        vm.expectRevert("ERC721: caller is not token owner or approved");
        lendingPool.borrow(
            nftIds,
            PRICE,
            DEADLINE,
            MAX_INTEREST,
            _totalToBorrow(PRICE, 2),
            v,
            r,
            s
        );
    }

    function testRevert_userBorrowNftsWithSameIds() public {
        _ownerDepositIntoLendingPool();

        (uint8 v, bytes32 r, bytes32 s) = _generateSignature();
        uint256[] memory nftIds = new uint256[](2);
        nftIds[0] = 0;
        nftIds[1] = 0;

        vm.startPrank(user);
        nft.setApprovalForAll(address(lendingPool), true);

        vm.expectRevert("ERC721: token already minted");
        lendingPool.borrow(
            nftIds,
            PRICE,
            DEADLINE,
            MAX_INTEREST,
            _totalToBorrow(PRICE, 2),
            v,
            r,
            s
        );
        vm.stopPrank();
    }

    function test_userBorrowNftsCallerReceivesEth() public {
        _ownerDepositIntoLendingPool();

        uint256 prevEth = user.balance;
        _userBorrowNft();
        uint256 postEth = user.balance;

        assertEq(postEth - prevEth, _totalToBorrow(PRICE, 2));
    }

    function test_TokenUri() public {
        _ownerDepositIntoLendingPool();
        _userBorrowNft();

        LendingPool.Loan memory loan = _generateLoan(
            0,
            _totalToBorrow(PRICE, 2),
            0,
            1 ether
        );
        uint256 loanId = lendingPool.getLoanId(
            loan.nft,
            loan.interest,
            loan.startTime,
            loan.borrowed
        );
        assertEq(
            lendingPool.tokenURI(loanId),
            string(
                abi.encodePacked(
                    "https://nft.llamalend.com/nft/",
                    Strings.toString(chainId),
                    "/",
                    Strings.toHexString(address(lendingPool)),
                    "/",
                    Strings.toHexString(address(nft)),
                    "/",
                    Strings.toString(loanId)
                )
            )
        );
    }

    function test_CurrentAnnualInterest() public {
        _ownerDepositIntoLendingPool();
        _userBorrowNft();

        assertGe(
            lendingPool.currentAnnualInterest(0),
            0.4 ether + 0.16 ether - 30000000
        );
        assertLe(
            lendingPool.currentAnnualInterest(0),
            0.4 ether + 0.16 ether + 30000000
        );
        assertGe(
            lendingPool.currentAnnualInterest(ONE_TENTH_OF_AN_ETH),
            0.4 ether + 0.2 ether - 40000000
        );
        assertLe(
            lendingPool.currentAnnualInterest(ONE_TENTH_OF_AN_ETH),
            0.4 ether + 0.2 ether + 40000000
        );
    }

    function test_CurrentAnnualInterestAccruesOverTime() public {
        _ownerDepositIntoLendingPool();
        _userBorrowNft();

        LendingPool.Loan[] memory loans = new LendingPool.Loan[](1);
        loans[0] = _generateLoan(1, _totalToBorrow(PRICE, 2), 0, 1 ether);

        vm.warp(block.timestamp + (3600 * 24 * 7)); // 1 week

        vm.prank(user);
        lendingPool.repay{value: ONE_TENTH_OF_AN_ETH * 2}(loans, user);

        assertGe(
            lendingPool.currentAnnualInterest(0),
            0.4 ether + 0.08 ether - 175459503840000
        );
        assertLe(
            lendingPool.currentAnnualInterest(0),
            0.4 ether + 0.08 ether + 175459503840000
        );
    }

    function test_LiquidationOfExpiredLoans() public {
        _ownerDepositIntoLendingPool();
        _userBorrowNft();

        vm.prank(owner);
        lendingPool.addLiquidator(liquidator);

        LendingPool.Loan memory loan = _generateLoan(
            0,
            _totalToBorrow(PRICE, 2),
            0,
            1 ether
        );

        vm.warp(block.timestamp + MAX_LOAN_LENGTH + 1); // 2 weeks + 1s

        (, uint256 totalRepay, , , ) = lendingPool.infoToRepayLoan(loan);
        assertGe(
            totalRepay,
            ((0.48 ether * 14) / uint256(365) / 10) + 0.1 ether - 5604925205000
        );
        assertLe(
            totalRepay,
            ((0.48 ether * 14) / uint256(365) / 10) + 0.1 ether + 5604925205000
        );

        vm.prank(liquidator);
        lendingPool.doEffectiveAltruism(loan, liquidator);
        assertEq(nft.ownerOf(0), liquidator);

        LlamaLendFactory.LoanRepayment[]
            memory loanInfos = new LlamaLendFactory.LoanRepayment[](1);
        loanInfos[0] = _generateLoanRepayment(loan);

        vm.prank(user);
        vm.expectRevert("ERC721: invalid token ID");
        factory.repay{value: ONE_TENTH_OF_AN_ETH * 2}(loanInfos);
    }

    function testRevert_LiquidationOfUnexpiredLoans() public {
        _ownerDepositIntoLendingPool();
        _userBorrowNft();

        vm.prank(owner);
        lendingPool.addLiquidator(liquidator);

        LendingPool.Loan memory loan = _generateLoan(
            0,
            _totalToBorrow(PRICE, 2),
            0,
            1 ether
        );

        vm.warp(block.timestamp + (3600 * 24 * 7)); // 1 week

        vm.prank(liquidator);
        vm.expectRevert("not expired");
        lendingPool.doEffectiveAltruism(loan, liquidator);
    }

    function testRevert_RepayByNonOwnerOfLoan() public {
        _ownerDepositIntoLendingPool();
        _userBorrowNft();

        LlamaLendFactory.LoanRepayment[]
            memory loanInfos = new LlamaLendFactory.LoanRepayment[](1);
        loanInfos[0] = _generateLoanRepayment(
            _generateLoan(0, _totalToBorrow(PRICE, 2), 0, 1 ether)
        );
        address randomUser = vm.addr(0x99);

        vm.deal(randomUser, 1000 ether); // seed ether balance
        vm.prank(randomUser);
        vm.expectRevert("not owner");
        factory.repay{value: ONE_TENTH_OF_AN_ETH * 2}(loanInfos);
    }

    function test_RepayByOwnerOfLoan() public {
        _ownerDepositIntoLendingPool();
        _userBorrowNft();

        LendingPool.Loan[] memory loans = new LendingPool.Loan[](1);
        loans[0] = _generateLoan(1, _totalToBorrow(PRICE, 2), 0, 1 ether);

        assertGe(loans[0].interest, (0.48 ether / SECONDS_PER_YEAR) - 10000);
        assertLe(loans[0].interest, (0.48 ether / SECONDS_PER_YEAR) + 10000);

        vm.warp(block.timestamp + (3600 * 24 * 7)); // 1 week

        uint256 prevEth = user.balance;
        vm.prank(user);
        lendingPool.repay{value: ONE_TENTH_OF_AN_ETH * 2}(loans, user);
        uint256 postEth = user.balance;
        assertGe(
            prevEth - postEth,
            uint256(PRICE / 2) -
                (((0.48 ether * uint256(7)) / uint256(365)) * 0.1 ether) /
                1 ether
        );
        assertLe(
            prevEth - postEth,
            uint256(PRICE / 2) +
                (((0.48 ether * uint256(7)) / uint256(365)) * 0.1 ether) /
                1 ether
        );
        assertEq(nft.ownerOf(1), user);
    }

    function testRevert_RepayByOwnerOfLoanTwice() public {
        _ownerDepositIntoLendingPool();
        _userBorrowNft();

        LendingPool.Loan[] memory loans = new LendingPool.Loan[](1);
        loans[0] = _generateLoan(1, _totalToBorrow(PRICE, 2), 0, 1 ether);

        vm.warp(block.timestamp + (3600 * 24 * 7)); // 1 week

        vm.startPrank(user);
        lendingPool.repay{value: ONE_TENTH_OF_AN_ETH * 2}(loans, user);

        vm.expectRevert("ERC721: invalid token ID");
        lendingPool.repay{value: ONE_TENTH_OF_AN_ETH * 2}(loans, user);
        vm.stopPrank();
    }

    function test_RepayMulitplePools() public {
        vm.startPrank(owner);
        LendingPool lendingPool2 = factory.createPool(
            oracle,
            ONE_ETH,
            address(nft),
            startMaxDailyBorrows,
            "TubbyLoan",
            "TL",
            uint96(SECONDS_PER_DAY),
            interests
        );
        lendingPool.deposit{value: ONE_ETH}();
        lendingPool2.deposit{value: ONE_ETH}();
        vm.stopPrank();

        vm.startPrank(user);
        nft.setApprovalForAll(address(lendingPool), true);
        nft.setApprovalForAll(address(lendingPool2), true);

        (uint8 v, bytes32 r, bytes32 s) = _generateSignature();
        uint256[] memory nftIds = new uint256[](6);
        nftIds[0] = 0;
        nftIds[1] = 1;
        nftIds[2] = 2;
        nftIds[3] = 3;
        nftIds[4] = 4;
        nftIds[5] = 5;
        lendingPool.borrow(
            nftIds,
            PRICE,
            DEADLINE,
            MAX_INTEREST,
            _totalToBorrow(PRICE, 6),
            v,
            r,
            s
        );

        bytes32 digest = sigUtils.getDigest(
            PRICE,
            DEADLINE + 1e8,
            address(nft),
            chainId
        );
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(oraclePrivateKey, digest);
        nftIds = new uint256[](1);
        nftIds[0] = 6;
        lendingPool2.borrow(
            nftIds,
            PRICE,
            DEADLINE + 1e8,
            MAX_INTEREST,
            _totalToBorrow(PRICE, 1),
            v2,
            r2,
            s2
        );

        LlamaLendFactory.LoanRepayment[]
            memory loanInfos = new LlamaLendFactory.LoanRepayment[](2);
        loanInfos[0] = _generateLoanRepayment(
            _generateLoan(0, _totalToBorrow(PRICE, 6), 0, 1 ether)
        );

        LendingPool.Loan[] memory loans = new LendingPool.Loan[](1);
        loans[0] = _generateLoan(6, _totalToBorrow(PRICE, 1), 0, 1 ether);
        loanInfos[1] = LlamaLendFactory.LoanRepayment(
            address(lendingPool2),
            loans
        );

        factory.repay{value: ONE_ETH}(loanInfos);
        vm.stopPrank();
    }

    function testRevert_EmergencyShutdownCallDirectlyOnLendingPool() public {
        vm.prank(owner);
        vm.expectRevert();
        lendingPool.emergencyShutdown();
    }

    function test_EmergencyShutdown() public {
        bytes32 digest = sigUtils.getDigest(
            PRICE,
            DEADLINE + 1e8,
            address(nft),
            chainId
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(oraclePrivateKey, digest);
        address[] memory lendingPools = new address[](1);
        lendingPools[0] = address(lendingPool);

        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        factory.emergencyShutdown(lendingPools);

        uint256[] memory nftIds = new uint256[](4);
        nftIds[0] = 1;
        nftIds[1] = 2;
        nftIds[2] = 3;
        nftIds[3] = 4;

        vm.prank(owner);
        lendingPool.deposit{value: ONE_ETH}();

        vm.startPrank(user);
        nft.setApprovalForAll(address(lendingPool), true);
        lendingPool.borrow(
            nftIds,
            PRICE,
            DEADLINE + 1e8,
            MAX_INTEREST,
            _totalToBorrow(PRICE, 4),
            v,
            r,
            s
        );
        vm.stopPrank();

        vm.prank(owner);
        factory.emergencyShutdown(lendingPools);
        assertEq(lendingPool.maxPrice(), 0);

        nftIds = new uint256[](1);
        nftIds[0] = 4;

        vm.prank(user);
        vm.expectRevert("max price");
        lendingPool.borrow(
            nftIds,
            PRICE,
            DEADLINE + 1e8,
            MAX_INTEREST,
            _totalToBorrow(PRICE, 4),
            v,
            r,
            s
        );

        LendingPool.Loan memory loan = _generateLoan(
            3,
            _totalToBorrow(PRICE, 4),
            0,
            1 ether
        );
        LlamaLendFactory.LoanRepayment[]
            memory loanInfos = new LlamaLendFactory.LoanRepayment[](1);
        loanInfos[0] = _generateLoanRepayment(loan);

        vm.prank(user);
        factory.repay{value: ONE_TENTH_OF_AN_ETH * 2}(loanInfos);
    }

    function testRevert_WithdrawByNonOwner() public {
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        lendingPool.withdraw(address(lendingPool).balance);
    }

    function test_WithdrawByOwner() public {
        uint256 ownerPrevEth = owner.balance;
        uint256 lendingPoolEth = address(lendingPool).balance;

        vm.prank(owner);
        lendingPool.withdraw(lendingPoolEth);

        uint256 ownerPostEth = owner.balance;
        assertEq(ownerPostEth - ownerPrevEth, lendingPoolEth);
        assertEq(address(lendingPool).balance, 0);
    }

    function testRevert_TransferLoanNftsTo0x0() public {
        _ownerDepositIntoLendingPool();
        _userBorrowNft();

        LendingPool.Loan memory loan = _generateLoan(
            0,
            _totalToBorrow(PRICE, 2),
            0,
            1 ether
        );
        uint256 loanId = lendingPool.getLoanId(
            loan.nft,
            loan.interest,
            loan.startTime,
            loan.borrowed
        );

        vm.prank(user);
        vm.expectRevert("ERC721: transfer to the zero address");
        lendingPool.transferFrom(user, address(0), loanId);
    }

    function _generateSignature()
        private
        returns (
            uint8 v,
            bytes32 r,
            bytes32 s
        )
    {
        bytes32 digest = sigUtils.getDigest(
            PRICE,
            DEADLINE,
            address(nft),
            chainId
        );
        (v, r, s) = vm.sign(oraclePrivateKey, digest);
    }

    function _generateLoan(
        uint256 nftId,
        uint256 totalToBorrow,
        uint256 totalBorrowedBeforeLoan,
        uint256 lendingPoolEthBalanceBeforeLoan
    ) private view returns (LendingPool.Loan memory) {
        return
            LendingPool.Loan(
                nftId,
                _calculateInterest(
                    totalToBorrow,
                    totalBorrowedBeforeLoan,
                    lendingPoolEthBalanceBeforeLoan
                ),
                uint40(block.timestamp),
                uint216((PRICE * LTV) / 1e18)
            );
    }

    function _generateLoanRepayment(LendingPool.Loan memory loan)
        private
        view
        returns (LlamaLendFactory.LoanRepayment memory)
    {
        LendingPool.Loan[] memory loans = new LendingPool.Loan[](1);
        loans[0] = loan;
        return LlamaLendFactory.LoanRepayment(address(lendingPool), loans);
    }

    function _totalToBorrow(uint216 price, uint256 n)
        private
        pure
        returns (uint256)
    {
        return (price * n * LTV) / ONE_ETH;
    }

    function _ownerDepositIntoLendingPool() private {
        vm.prank(owner);
        lendingPool.deposit{value: ONE_ETH}();
    }

    function _userBorrowNft() private {
        (uint8 v, bytes32 r, bytes32 s) = _generateSignature();
        uint256[] memory nftIds = new uint256[](2);
        nftIds[0] = 0;
        nftIds[1] = 1;

        vm.startPrank(user);
        nft.setApprovalForAll(address(lendingPool), true);
        lendingPool.borrow(
            nftIds,
            PRICE,
            DEADLINE,
            MAX_INTEREST,
            _totalToBorrow(PRICE, nftIds.length),
            v,
            r,
            s
        );
        vm.stopPrank();
    }

    function _calculateInterest(
        uint256 priceOfNextItems,
        uint256 totalBorrowedBeforeLoan,
        uint256 lendingPoolEthBalanceBeforeLoan
    ) private view returns (uint256) {
        uint256 borrowed = priceOfNextItems / 2 + totalBorrowedBeforeLoan;
        uint256 variableRate = (borrowed *
            interests.maxVariableInterestPerEthPerSecond) /
            (lendingPoolEthBalanceBeforeLoan + totalBorrowedBeforeLoan);
        return interests.minimumInterest + variableRate;
    }
}
