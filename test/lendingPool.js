const { expect } = require("chai");
const { ethers, network } = require("hardhat");
const { sign, getContract } = require('../scripts/utils')

// interest is correctly applied
// clawing works

const userAddress = "0x71a15Ac12ee91BF7c83D08506f3a3588143898B5"
const nftAddress = "0xf5de760f2e916647fd766B4AD9E85ff943cE3A2b"

const eth1 = "1000000000000000000"
const eth01 = "100000000000000000"

describe("LendingPool", function () {
    it("oracle", async function () {
        const [owner, oracle] = await ethers.getSigners();
        const { lendingPool } = await getContract("LendingPool", [oracle.address, "100000000000000000", nftAddress])
        const price = 1
        const deadline = Math.round(Date.now() / 1000) + 1000;
        const nftContract = await lendingPool.nftContract()
        const signature = await sign(oracle, price, deadline, nftContract)
        await lendingPool.setMaxPrice("1000000000000000000") // 1eth
        await lendingPool.checkOracle(price, deadline, signature.v, signature.r, signature.s)
    })

    it("basic usage", async function () {
        const [owner, oracle] = await ethers.getSigners();
        const { lendingPool } = await getContract("LendingPool", [oracle.address, "1000000000000000000", nftAddress]) // 1eth
        const price = "100000000000000000" // 0.1eth
        const deadline = Math.round(Date.now() / 1000) + 1000;
        const nftContract = await lendingPool.nftContract()

        await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [userAddress],
        });
        const user = await ethers.provider.getSigner(userAddress); // nfts owned: 683971, 683972

        const nft = new ethers.Contract(nftContract, ["function ownerOf(uint) view returns (address)", "function setApprovalForAll(address operator, bool approved)"], owner)

        expect(await nft.ownerOf(683972)).to.equal(userAddress)
        await lendingPool.deposit({ value: eth1 })
        await expect(lendingPool.connect(oracle).deposit({ value: eth1 })).to.be.revertedWith("Ownable: caller is not the owner");

        const signature = await sign(oracle, price, deadline, nftContract)

        await nft.connect(user).setApprovalForAll(lendingPool.address, true)
        // only owner can borrow nfts
        await expect(lendingPool.connect(owner).borrow([683971, 683972], price, deadline, signature.v, signature.r, signature.s)).to.be.revertedWith("not owner");
        // cant borrow same nft twice
        await expect(lendingPool.connect(user).borrow([683971, 683971], price, deadline, signature.v, signature.r, signature.s)).to.be.revertedWith("not owner");
        {
            const prevEth = await ethers.provider.getBalance(userAddress);
            const tx = await (await lendingPool.connect(user).borrow([683971, 683972], price, deadline, signature.v, signature.r, signature.s)).wait()
            const postEth = await ethers.provider.getBalance(userAddress);
            expect(await nft.ownerOf(683971)).to.equal(lendingPool.address)
            expect(postEth.sub(prevEth)).to.be.equal(ethers.BigNumber.from(price).mul(2).sub(tx.gasUsed*tx.effectiveGasPrice))
        }
        expect(await lendingPool.tokenURI(1)).to.eq("https://api.tubbysea.com/nft/ethereum/0xf5de760f2e916647fd766b4ad9e85ff943ce3a2b/1")

        expect(Number(await lendingPool.currentAnnualInterest(0))).to.be.approximately(0.16e18, 200000)
        expect(Number(await lendingPool.currentAnnualInterest(eth01))).to.be.approximately(0.24e18, 200000)
        await network.provider.send("evm_increaseTime", [3600 * 24 * 7]) // 1 week
        //await network.provider.send("evm_mine")
        await expect(lendingPool.connect(owner).claw(0)).to.be.revertedWith("not expired");
        expect(Number((await lendingPool.infoToRepayLoan(1)).totalRepay)).to.be.approximately((0.16 * 7 / 365 * 0.1 + 0.1) * 1e18, 80000000)

        {
            await expect(lendingPool.connect(owner).repay(1, {value: (eth01*2).toFixed(0)})).to.be.revertedWith("not owner")
            const prevEth = await ethers.provider.getBalance(userAddress);
            const tx = await (await lendingPool.connect(user).repay(1, {value: (eth01*2).toFixed(0)})).wait()
            const postEth = await ethers.provider.getBalance(userAddress);
            console.log("first repay: ", Number(postEth.sub(prevEth).toString()) + (tx.gasUsed*tx.effectiveGasPrice))
            expect(Number(postEth.sub(prevEth).toString())).to.be.approximately(
                -Number(ethers.BigNumber.from(price).add((0.16*7/365*0.1e18).toFixed(0)).add(tx.gasUsed*tx.effectiveGasPrice).toString()), 10007356530)
            expect(await nft.ownerOf(683972)).to.equal(userAddress)
        }

        // can't repay twice
        await expect(lendingPool.connect(user).repay(1, {value: (eth01*2).toFixed(0)})).to.be.revertedWith("OwnerQueryForNonexistentToken()");

        await network.provider.send("evm_increaseTime", [3600 * 24 * 7]) // 1 week
        await network.provider.send("evm_mine")
        expect(Number(await lendingPool.currentAnnualInterest(0))).to.be.approximately(0.08e18, 175459503840000)

        console.log("second loan", (await lendingPool.infoToRepayLoan(0)).totalRepay.toString())
        expect(Number((await lendingPool.infoToRepayLoan(0)).totalRepay)).to.be.approximately(((0.16 * 7 + 0.08 * 7) / 365 * 0.1 + 0.1) * 1e18, 46049252050)
        await expect(lendingPool.connect(user).repay(0, {value: (eth01*2).toFixed(0)})).to.be.revertedWith("expired");
        await lendingPool.connect(owner).claw(0);
        expect(await nft.ownerOf(683971)).to.equal(owner.address)

        expect(Number(await lendingPool.currentAnnualInterest(0))).to.eq(0)
        await expect(lendingPool.connect(user).withdraw(await ethers.provider.getBalance(lendingPool.address))).to.be.revertedWith("Ownable: caller is not the owner");
        await lendingPool.withdraw(await ethers.provider.getBalance(lendingPool.address))
    })
})