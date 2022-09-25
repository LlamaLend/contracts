const { ethers } = require("hardhat");

describe("ListNfts", function () {
  it("oracle", async function () {
    this.timeout(1000000);
    const ListNfts = await ethers.getContractFactory("ListNfts");

    const listNfts = await ListNfts.deploy();
    await listNfts.deployed();

    const owners = await listNfts.getOwnedNfts(
      "0x50664ede715e131f584d3e7eaabd7818bb20a068", //yfimaxi.eth
      listNfts.address, 
      0, 
      5e3
    );
  });
});