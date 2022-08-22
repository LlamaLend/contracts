const { expect } = require("chai");
const { ethers } = require("hardhat");
const {getContract} = require('../scripts/utils')

describe("ListNfts", function () {
  it("oracle", async function () {
    this.timeout(1000000);
    const { lendingPool } = await getContract("ListNfts", [])
    const owners = await lendingPool.getOwnedNfts("0x50664ede715e131f584d3e7eaabd7818bb20a068", //yfimaxi.eth
     "0xCa7cA7BcC765F77339bE2d648BA53ce9c8a262bD", 0, 5e3)
})
})