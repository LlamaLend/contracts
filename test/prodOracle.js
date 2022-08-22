const {getContract} = require('../scripts/utils')
const fetch = require("node-fetch")

describe("Prod Oracle", function () {
  it("oracle", async function () {
    const { lendingPool } = await getContract("LendingPool", ["0xab2f947d22ab9ccfc34c9d257fce971c05042b59", "100000000000000000"])
    const {price, deadline, signature} = await fetch("https://api.tubbysea.com/quote/tubby").then(r=>r.json())
    await lendingPool.setMaxPrice("1000000000000000000000000000")
    await lendingPool.checkOracle(price, deadline, signature.v, signature.r, signature.s)
})
it("goerli oracle", async function () {
  const LendingPool = await hre.ethers.getContractFactory("LendingPool");
  const lendingPool = await LendingPool.attach("0x73243f724272d5049314428f848e2a4bb273e630");
  const {price, deadline, signature} = await fetch("https://api.tubbysea.com/quote/tubby").then(r=>r.json())
  await lendingPool.checkOracle(price, deadline, signature.v, signature.r, signature.s)
})
})