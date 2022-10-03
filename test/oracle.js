const { sign } = require('../scripts/utils');

describe("LendingPool", function () {
    it("generates fake signature for goerli", async function () {
        const [_owner, oracle] = await ethers.getSigners();
        const deadline = Math.round(Date.now() / 1000) + 3600*24*30; // +1 month
        const price = "10000000000000000" // 0.01 ETH
        const nftContract = "0xf5de760f2e916647fd766b4ad9e85ff943ce3a2b"  // MultiFaucet NFT
        const sig = await sign(oracle, price, deadline, nftContract, 5)
        console.log(`Oracle address: ${oracle.address}\nSignature:`, { 
            price, 
            deadline, 
            "normalizedNftContract": nftContract.toLowerCase(), 
            "signature": {
                "v": sig.v, 
                "r": sig.r, 
                "s": sig.s
            } 
        })
    })
})