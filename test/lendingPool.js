const { expect } = require("chai");
const { BigNumber } = require("ethers");
const { ethers, network } = require("hardhat");
const { sign, deployAll } = require('../scripts/utils');

const ONE_ETH = "1000000000000000000";
const ONE_TENTH_OF_AN_ETH = "100000000000000000";
const TWO_TENTHS_OF_AN_ETH = "200000000000000000";

const startMaxDailyBorrows = ONE_ETH
const SECONDS_PER_DAY = 24 * 60 * 60
const DAYS_PER_YEAR = 365;
const SECONDS_PER_YEAR = DAYS_PER_YEAR * SECONDS_PER_DAY;
const INTEREST_WEI_PER_ETH_PER_YEAR = 0.8e18;
const MAX_INTEREST = "700000000000000000"; // 0.7e18
const DEADLINE = Math.round(Date.now() / 1000) + 1000;
const MINIMUM_INTEREST = "12683916793"; // 40%
const LTV = "500000000000000000"; // 50%
const PRICE = TWO_TENTHS_OF_AN_ETH;

async function getLoan(lendingPool, n){
    const loanInfo = await lendingPool.queryFilter(lendingPool.filters.LoanCreated());
    return {
        nft: loanInfo[n].args.nft,
        interest:loanInfo[n].args.interest,
        startTime:loanInfo[n].args.startTime,
        borrowed: loanInfo[n].args.borrowed,
    }
}

function totalToBorrow(price, n){
    return BigNumber.from(price).mul(n).mul(LTV).div(ONE_ETH)
}

describe("LendingPool", function () {
    let owner;
    let oracle;
    let liquidator;
    let factory;
    let lendingPool;
    let nft;
    let user;
    let chainId;

    this.beforeAll(async function () {
        const [ _owner, _oracle, _liquidator, _user ] = await ethers.getSigners();
        this.owner = _owner;
        this.oracle = _oracle;
        this.liquidator = _liquidator;
        this.user = _user;

        const { factory, lendingPool, mockNft } = await deployAll(
            this.oracle.address, 
            ONE_TENTH_OF_AN_ETH, 
            startMaxDailyBorrows, 
            "TubbyLoan", 
            "TL", 
            14 * SECONDS_PER_DAY, 
            Math.round(INTEREST_WEI_PER_ETH_PER_YEAR / SECONDS_PER_YEAR),
            MINIMUM_INTEREST,
            LTV,
        );

        await mockNft.mint(10, this.user.address);
        
        this.factory = factory;
        this.lendingPool = lendingPool;
        this.nft = mockNft;
        this.chainId = await _owner.getChainId();
    });

    it("accepts signatures from a price oracle", async function () {
        const signature = await sign(this.oracle, PRICE, DEADLINE, this.nft.address, this.chainId);
        await this.lendingPool.setMaxPrice(ONE_ETH) // 1eth
        await this.lendingPool.checkOracle(PRICE, DEADLINE, signature.v, signature.r, signature.s)
    });

    it("can not use expired oracle signatures", async function() {
        // TODO
    });

    it("has expected starting conditions", async function() {
        expect(await this.nft.ownerOf(1)).to.equal(this.user.address);
    });

    it("currentAnnualInterest() works even when there's 0 eth in contract", async function() {
        expect(await this.lendingPool.currentAnnualInterest(0)).to.equal(BigNumber.from(MINIMUM_INTEREST).mul(SECONDS_PER_YEAR)); // minimum interest
    });

    it("allows owner to deposit", async function() {
        await this.lendingPool.deposit({ value: ONE_ETH });
    });

    it ("blocks non-owners from depositing", async function() {
        await expect(this.lendingPool.connect(this.oracle).deposit({ value: ONE_ETH })).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("allows owner to add liquidators", async function() {
        await this.lendingPool.connect(this.owner).addLiquidator(this.liquidator.address)
    })

    it ("blocks non-owners from adding liquidators", async function() {
        await expect(this.lendingPool.connect(this.oracle).addLiquidator(this.liquidator.address)).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("blocks non-owners from borrowing NFTs", async function() {
        const signature = await sign(this.oracle, PRICE, DEADLINE, this.nft.address, this.chainId);
        await expect(this.lendingPool.connect(this.owner).borrow([0, 1], PRICE, DEADLINE, MAX_INTEREST, totalToBorrow(PRICE, 2), signature.v, signature.r, signature.s)).to.be.revertedWith("ERC721: transfer caller is not owner nor approved");
    });

    it("blocks users from borrowing the same NFT twice", async function() {
        const signature = await sign(this.oracle, PRICE, DEADLINE, this.nft.address, this.chainId);
        await this.nft.connect(this.user).setApprovalForAll(this.lendingPool.address, true);

        await expect(this.lendingPool.connect(this.user).borrow([0, 0], PRICE, DEADLINE, MAX_INTEREST, totalToBorrow(PRICE, 2), signature.v, signature.r, signature.s)).to.be.revertedWith("ERC721: token already minted");
    });

    it("sends eth to the user upon borrowing their NFTs", async function() {
        const signature = await sign(this.oracle, PRICE, DEADLINE, this.nft.address, this.chainId);
        const totalBorrowed = totalToBorrow(PRICE, 2)
        const prevEth = await ethers.provider.getBalance(this.user.address);
        const pendingTx = await this.lendingPool.connect(this.user).borrow([0, 1], PRICE, DEADLINE, MAX_INTEREST, totalBorrowed, signature.v, signature.r, signature.s);
        
        const tx = await pendingTx.wait();

        const postEth = await ethers.provider.getBalance(this.user.address);

        expect(await this.nft.ownerOf(0)).to.equal(this.lendingPool.address)

        expect(postEth.sub(prevEth)).to.be.equal(ethers.BigNumber.from(totalBorrowed).sub(tx.gasUsed * tx.effectiveGasPrice))
    });

    it("prevents non-owners from repaying loans", async function() {
        const loanInfo = await getLoan(this.lendingPool, 1);
        await expect(this.lendingPool.connect(this.owner).repay([loanInfo], { value: (Number(ONE_TENTH_OF_AN_ETH) * 2).toFixed(0) })).to.be.revertedWith("not owner");
    });

    it("returns a correct tokenURI", async function () {
        const loanInfo = await this.lendingPool.queryFilter(this.lendingPool.filters.LoanCreated());
        const id = loanInfo[0].args.loanId
        expect(await this.lendingPool.tokenURI(id)).to.eq(`https://nft.llamalend.com/nft/31337/${this.lendingPool.address.toLowerCase()}/${this.nft.address.toLowerCase()}/${id.toString()}`)
    });

    it("returns correct interest rates", async function () {
        expect(Number(await this.lendingPool.currentAnnualInterest(0))).to.be.approximately(0.4e18 + 0.16e18, 30000000)
        expect(Number(await this.lendingPool.currentAnnualInterest(ONE_TENTH_OF_AN_ETH))).to.be.approximately(0.4e18 + 0.2e18, 40000000)
    });

    it("does not allow liquidation of unexpired loans", async function () {
        await network.provider.send("evm_increaseTime", [3600 * 24 * 7]) // 1 week
        await network.provider.send("evm_mine")
        const loanInfo = await getLoan(this.lendingPool, 0);
        await expect(this.lendingPool.connect(this.liquidator).doEffectiveAltruism(loanInfo, this.liquidator.address)).to.be.revertedWith("not expired");
    });

    it("allows owners to repay their loans", async function () {
        const loanInfo = await getLoan(this.lendingPool, 1);
        expect(Number(loanInfo.interest)).to.be.approximately(0.48e18/SECONDS_PER_YEAR, 1e4);
        const prevEth = await ethers.provider.getBalance(this.user.address);
        const tx = await (await this.lendingPool.connect(this.user).repay([loanInfo], { value: (Number(ONE_TENTH_OF_AN_ETH) * 2).toFixed(0) })).wait()
        const postEth = await ethers.provider.getBalance(this.user.address);
                
        console.log("first repay: ", Number(postEth.sub(prevEth).toString()) + (tx.gasUsed * tx.effectiveGasPrice))
        
        expect(Number(postEth.sub(prevEth).toString())).to.be.approximately(
            -Number(ethers.BigNumber.from(PRICE).div(2).add((0.48 * 7 / 365 * 0.1e18).toFixed(0)).add(tx.gasUsed * tx.effectiveGasPrice).toString()), 
            10007356530
        );

        expect(await this.nft.ownerOf(1)).to.equal(this.user.address)
    });

    it("blocks owners from repaying the same loan twice", async function () {   
        const loanInfo = await getLoan(this.lendingPool, 1);
        await expect(this.lendingPool.connect(this.user).repay([loanInfo], { value: (Number(ONE_TENTH_OF_AN_ETH) * 2).toFixed(0) })).to.be.revertedWith("ERC721: owner query for nonexistent token");
    });

    it("accrues interest over time", async function () {
        await network.provider.send("evm_increaseTime", [3600 * 24 * 7]) // 1 week
        await network.provider.send("evm_mine")
        expect(Number(await this.lendingPool.currentAnnualInterest(0))).to.be.approximately(0.4e18 + 0.08e18, 175459503840000)
    })

    it("allows liquidation of expired loans", async function () {
        const loanInfo = await getLoan(this.lendingPool, 0);
        console.log("second loan", (await this.lendingPool.infoToRepayLoan(loanInfo)).totalRepay.toString())
        expect(Number((await this.lendingPool.infoToRepayLoan(loanInfo)).totalRepay)).to.be.approximately(((0.48 * 14) / 365 * 0.1 + 0.1) * 1e18, 5604925205000)
        await this.lendingPool.connect(this.liquidator).doEffectiveAltruism(loanInfo, this.liquidator.address);
        expect(await this.nft.ownerOf(0)).to.equal(this.liquidator.address)
        await expect(this.lendingPool.connect(this.user).repay([loanInfo], { value: (Number(ONE_TENTH_OF_AN_ETH) * 2).toFixed(0) })).to.be.revertedWith("ERC721: owner query for nonexistent token");
    })

    it("correctly handles emergency shutdowns", async function () {
        //expect(Number(await this.lendingPool.currentAnnualInterest(0))).to.eq(0)

        const signature2 = await sign(this.oracle, PRICE, DEADLINE + 1e8, this.nft.address, this.chainId)
        await expect(this.factory.connect(this.user).emergencyShutdown([0])).to.be.revertedWith('Ownable: caller is not the owner');
        
        await this.lendingPool.connect(this.user).borrow([1, 2, 3], PRICE, DEADLINE + 1e8, MAX_INTEREST, totalToBorrow(PRICE, 3), signature2.v, signature2.r, signature2.s)
        await this.factory.connect(this.owner).emergencyShutdown([0])
        await expect(this.lendingPool.connect(this.user).borrow([4], PRICE, DEADLINE + 1e8, MAX_INTEREST, totalToBorrow(PRICE, 1), signature2.v, signature2.r, signature2.s))
            .to.be.revertedWith("max price");
        const loanInfo = await getLoan(this.lendingPool, 3);
        await this.lendingPool.connect(this.user).repay([loanInfo], { value: (Number(ONE_TENTH_OF_AN_ETH) * 2).toFixed(0) })
    });

    it ("blocks non-owners from withdrawing", async function () {
        await expect(this.lendingPool.connect(this.user).withdraw(await ethers.provider.getBalance(this.lendingPool.address))).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("allows owners to withdraw", async function() {
        await this.lendingPool.withdraw(await ethers.provider.getBalance(this.lendingPool.address))
    })
})