const { expect } = require("chai");
const { ethers, network } = require("hardhat");
const { sign, deployAll } = require('../scripts/utils');

const ONE_ETH = "1000000000000000000";
const ONE_TENTH_OF_AN_ETH = "100000000000000000";

const userAddress = "0x71a15Ac12ee91BF7c83D08506f3a3588143898B5"
const nftAddress = "0xf5de760f2e916647fd766B4AD9E85ff943cE3A2b"
const startMaxDailyBorrows = ONE_ETH
const SECONDS_PER_DAY = 24 * 60 * 60
const DAYS_PER_YEAR = 365;
const INTEREST_WEI_PER_ETH_PER_YEAR = 0.8e18;
const DEADLINE = Math.round(Date.now() / 1000) + 1000;
const PRICE = ONE_TENTH_OF_AN_ETH;

describe("LendingPool", function () {
    let owner;
    let oracle;
    let liquidator;
    let factory;
    let lendingPool;
    let nft;
    let user;

    this.beforeAll(async function () {
        const [ _owner, _oracle, _liquidator ] = await ethers.getSigners();
        this.owner = _owner;
        this.oracle = _oracle;
        this.liquidator = _liquidator;

        const { factory, lendingPool } = await deployAll(
            this.oracle.address, 
            ONE_TENTH_OF_AN_ETH, 
            nftAddress, 
            startMaxDailyBorrows, 
            "TubbyLoan", 
            "TL", 
            14 * SECONDS_PER_DAY, 
            Math.round(INTEREST_WEI_PER_ETH_PER_YEAR / DAYS_PER_YEAR / SECONDS_PER_DAY)
        );
        
        this.factory = factory;
        this.lendingPool = lendingPool;
        this.nft = new ethers.Contract(await this.lendingPool.nftContract(), ["function ownerOf(uint) view returns (address)", "function setApprovalForAll(address operator, bool approved)"], this.owner)

        await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [userAddress],
        });

        this.user = await ethers.provider.getSigner(userAddress);   
    });

    it("accepts signatures from a price oracle", async function () {
        const signature = await sign(this.oracle, PRICE, DEADLINE, this.nft.address);
        await this.lendingPool.setMaxPrice(ONE_ETH) // 1eth
        await this.lendingPool.checkOracle(PRICE, DEADLINE, signature.v, signature.r, signature.s)
    });

    it("can not use expired oracle signatures", async function() {
        // TODO
    });

    it("has expected starting conditions", async function() {
        expect(await this.nft.ownerOf(683972)).to.equal(userAddress);
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
        const signature = await sign(this.oracle, PRICE, DEADLINE, this.nft.address);
        await expect(this.lendingPool.connect(this.owner).borrow([683971, 683972], PRICE, DEADLINE, signature.v, signature.r, signature.s)).to.be.revertedWith("not owner");
    });

    it("blocks users from borrowing the same NFT twice", async function() {
        const signature = await sign(this.oracle, PRICE, DEADLINE, this.nft.address);
        // N.B.: baked into this test is the fact that `user` has already borrowed on Goerli at fork-time
        await this.nft.connect(this.user).setApprovalForAll(this.lendingPool.address, true);

        await expect(this.lendingPool.connect(this.user).borrow([683971, 683971], PRICE, DEADLINE, signature.v, signature.r, signature.s)).to.be.revertedWith("not owner");
    });

    it("sends eth to the user upon borrowing their NFTs", async function() {
        const signature = await sign(this.oracle, PRICE, DEADLINE, this.nft.address);
        const prevEth = await ethers.provider.getBalance(userAddress);
        // N.B.: baked into this test is the fact that `user` has already borrowed on Goerli at fork-time
        const pendingTx = await this.lendingPool.connect(this.user).borrow([683971, 683972], PRICE, DEADLINE, signature.v, signature.r, signature.s);
        
        const tx = await pendingTx.wait();

        const postEth = await ethers.provider.getBalance(userAddress);

        expect(await this.nft.ownerOf(683971)).to.equal(this.lendingPool.address)

        expect(postEth.sub(prevEth)).to.be.equal(ethers.BigNumber.from(PRICE).mul(2).sub(tx.gasUsed * tx.effectiveGasPrice))
    });

    it("prevents non-owners from repaying loans", async function() {
        await expect(this.lendingPool.connect(this.owner).repay([1], { value: (Number(ONE_TENTH_OF_AN_ETH) * 2).toFixed(0) })).to.be.revertedWith("not owner");
    });

    it("returns a correct tokenURI", async function () {
        expect(await this.lendingPool.tokenURI(1)).to.eq(`https://nft.llamalend.com/nft/31337/${this.lendingPool.address.toLowerCase()}/0xf5de760f2e916647fd766b4ad9e85ff943ce3a2b/1`)
    });

    it("returns correct interest rates", async function () {
        expect(Number(await this.lendingPool.currentAnnualInterest(0))).to.be.approximately(0.16e18, 200000)
        expect(Number(await this.lendingPool.currentAnnualInterest(ONE_TENTH_OF_AN_ETH))).to.be.approximately(0.24e18, 200000)
    });

    it("does not allow liquidation of unexpired loans", async function () {
        await network.provider.send("evm_increaseTime", [3600 * 24 * 7]) // 1 week
        await network.provider.send("evm_mine")
        await expect(this.lendingPool.connect(this.liquidator).claw(0, 0)).to.be.revertedWith("not expired");
    });

    it("allows owners to repay their loans", async function () {
        const prevEth = await ethers.provider.getBalance(userAddress);
        const tx = await (await this.lendingPool.connect(this.user).repay([1], { value: (Number(ONE_TENTH_OF_AN_ETH) * 2).toFixed(0) })).wait()
        const postEth = await ethers.provider.getBalance(userAddress);
                
        console.log("first repay: ", Number(postEth.sub(prevEth).toString()) + (tx.gasUsed * tx.effectiveGasPrice))
        
        expect(Number(postEth.sub(prevEth).toString())).to.be.approximately(
            -Number(ethers.BigNumber.from(PRICE).add((0.16 * 7 / 365 * 0.1e18).toFixed(0)).add(tx.gasUsed * tx.effectiveGasPrice).toString()), 
            10007356530
        );

        expect(await this.nft.ownerOf(683972)).to.equal(userAddress)
    });

    it("blocks owners from repaying the same loan twice", async function () {      
        await expect(this.lendingPool.connect(this.user).repay([1], { value: (Number(ONE_TENTH_OF_AN_ETH) * 2).toFixed(0) })).to.be.revertedWith("OwnerQueryForNonexistentToken()");
    });

    it("accrues interest over time", async function () {
        await network.provider.send("evm_increaseTime", [3600 * 24 * 7]) // 1 week
        await network.provider.send("evm_mine")
        expect(Number(await this.lendingPool.currentAnnualInterest(0))).to.be.approximately(0.08e18, 175459503840000)
    })

    it("allows liquidation of expired loans", async function () {
        console.log("second loan", (await this.lendingPool.infoToRepayLoan(0)).totalRepay.toString())
        expect(Number((await this.lendingPool.infoToRepayLoan(0)).totalRepay)).to.be.approximately(((0.16 * 7 + 0.08 * 7) / 365 * 0.1 + 0.1) * 1e18, 4604925205000)
        await this.lendingPool.connect(this.liquidator).claw(0, 0);
        expect(await this.nft.ownerOf(683971)).to.equal(this.liquidator.address)
        await expect(this.lendingPool.connect(this.user).repay([0], { value: (Number(ONE_TENTH_OF_AN_ETH) * 2).toFixed(0) })).to.be.revertedWith("OwnerQueryForNonexistentToken()");
    })

    it("correctly handles emergency shutdowns", async function () {
        expect(Number(await this.lendingPool.currentAnnualInterest(0))).to.eq(0)

        const signature2 = await sign(this.oracle, PRICE, DEADLINE + 1e8, this.nft.address)
        await expect(this.factory.connect(this.user).emergencyShutdown([0])).to.be.revertedWith('Ownable: caller is not the owner');
        
        await this.lendingPool.connect(this.user).borrow([683972, 683973, 683974], PRICE, DEADLINE + 1e8, signature2.v, signature2.r, signature2.s)
        await this.factory.connect(this.owner).emergencyShutdown([0])
        await expect(this.lendingPool.connect(this.user).borrow([683975], PRICE, DEADLINE + 1e8, signature2.v, signature2.r, signature2.s))
            .to.be.revertedWith("max price");
    });

    it ("blocks non-owners from withdrawing", async function () {
        await expect(this.lendingPool.connect(this.user).withdraw(await ethers.provider.getBalance(this.lendingPool.address))).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("allows owners to withdraw", async function() {
        await this.lendingPool.withdraw(await ethers.provider.getBalance(this.lendingPool.address))
    })
})