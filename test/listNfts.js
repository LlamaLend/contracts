const { expect } = require('chai');
const { ethers } = require('hardhat');

describe('ListNfts', function () {
  let mockNFT, mockEnumerableNFT, listNfts, owner, somebody, nobody;
  beforeEach(async function () {
    [owner, somebody, nobody] = await ethers.getSigners();

    const MockNFT = await ethers.getContractFactory('MockNFT');
    mockNFT = await MockNFT.deploy();
    await mockNFT.deployed();

    // quantity, recipient
    await mockNFT.mint(2, owner.address);
    await mockNFT.mint(3, somebody.address);
    await mockNFT.mint(100, owner.address);

    const MockEnumerableNFT = await ethers.getContractFactory(
      'MockEnumerableNFT'
    );
    mockEnumerableNFT = await MockEnumerableNFT.deploy();
    await mockEnumerableNFT.deployed();

    // quantity, recipient
    await mockEnumerableNFT.mint(2, owner.address);
    await mockEnumerableNFT.mint(3, somebody.address);
    await mockEnumerableNFT.mint(100, owner.address);

    const ListNfts = await ethers.getContractFactory('ListNfts');
    listNfts = await ListNfts.deploy();
    await listNfts.deployed();
  });

  it('full range, erc721', async function () {
    this.timeout(1000000);

    const owners = await listNfts.getOwnedNfts(
      owner.address,
      mockEnumerableNFT.address,
      0,
      5e3
    );

    // all of them should have been returned
    const balance = await mockNFT.balanceOf(owner.address);
    expect(balance).to.equal(102);
    expect(owners.length).to.equal(balance);
  });

  it('partial range, erc721', async function () {
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

  it('full range, erc721enumerable', async function () {
    this.timeout(1000000);

    const owners = await listNfts.getOwnedNfts(
      owner.address,
      mockEnumerableNFT.address,
      1,
      5e3
    );

    // all of them should have been returned
    const balance = await mockEnumerableNFT.balanceOf(owner.address);
    expect(owners.length).to.equal(balance);
  });

  it('partial range, erc721enumerable', async function () {
    this.timeout(1000000);

    const owners = await listNfts.getOwnedNfts(
      owner.address,
      mockEnumerableNFT.address,
      1,
      101
    );

    // in the range 1-100 inclusive three were minted to a different user
    expect(owners.length).to.equal(97);

    const owners2 = await listNfts.getOwnedNfts(
      owner.address,
      mockEnumerableNFT.address,
      101,
      201
    );
    // the remaining 5 will show up here.
    expect(owners2.length).to.equal(5);
  });

  it('no results', async function () {
    this.timeout(1000000);

    const owners = await listNfts.getOwnedNfts(
      nobody.address,
      mockNFT.address,
      1,
      101
    );

    expect(owners.length).to.equal(0);
  });
});
