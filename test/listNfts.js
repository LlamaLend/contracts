const { expect } = require('chai');
const { ethers } = require('hardhat');

describe('ListNfts', function () {
  let mockNFT, listNfts, owner, other;
  beforeEach(async function () {
    [owner, other] = await ethers.getSigners();

    const MockNFT = await ethers.getContractFactory('MockNFT');
    mockNFT = await MockNFT.deploy();
    await mockNFT.deployed();

    // quantity, recipient
    await mockNFT.mint(2, owner.address);
    await mockNFT.mint(3, other.address);
    await mockNFT.mint(100, owner.address);

    const ListNfts = await ethers.getContractFactory('ListNfts');
    listNfts = await ListNfts.deploy();
    await listNfts.deployed();
  });

  it('full range', async function () {
    this.timeout(1000000);

    const owners = await listNfts.getOwnedNfts(
      owner.address,
      mockNFT.address,
      1,
      5e3
    );

    // all of them should have been returned
    const balance = await mockNFT.balanceOf(owner.address);
    expect(owners.length).to.equal(balance);
  });

  it('partial range', async function () {
    this.timeout(1000000);

    const owners = await listNfts.getOwnedNfts(
      owner.address,
      mockNFT.address,
      1,
      101
    );

    // in the range 1-100 inclusive three were minted to a different user
    expect(owners.length).to.equal(97);

    const owners2 = await listNfts.getOwnedNfts(
      owner.address,
      mockNFT.address,
      101,
      201
    );
    // the remaining 5 will show up here.
    expect(owners2.length).to.equal(5);
  });
});
