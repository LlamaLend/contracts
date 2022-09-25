const { deployAll } = require('../scripts/utils')
const fetch = require("node-fetch")

// Only works on mainnet forks

describe("Prod Oracle", function () {
  it("oracle", async function () {
    const { lendingPool } = await deployAll(
      "0x4096b3f0e89c06e98d1095da7aefdd4b38eeb1e0", // oracle
      "60000000000000000", // 0.06 eth (_maxPrice)
      "0xCa7cA7BcC765F77339bE2d648BA53ce9c8a262bD", // tubby cats (_nftContract)
      "1000000000000000000", // 1 eth (_maxDailyBorrows)
      "TubbyLoan", // (_name_)
      "TL", // (_symbol)
      "1209600", // 2 weeks (_maxLoanLength)
      "25367833587", // 80% p.a. (_maxInterestPerEthPerSecond)
    )
    const { price, deadline, signature } = await fetch("https://oracle.llamalend.com/quote/1/0xCa7cA7BcC765F77339bE2d648BA53ce9c8a262bD").then(r => r.json())
    await lendingPool.setMaxPrice("1000000000000000000000000000")
    await lendingPool.checkOracle(price, deadline, signature.v, signature.r, signature.s)
  })
})