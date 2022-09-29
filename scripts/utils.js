const { ethers } = require("hardhat");

async function deployAll(
  _oracle,
  _maxPrice,
  _maxDailyBorrows,
  _name,
  _symbol,
  _maxLoanLength,
  _maxInterestPerEthPerSecond,
  _minimumInterest,
) {
  const Factory = await ethers.getContractFactory("LlamaLendFactory");
  const factory = await Factory.deploy();
  await factory.deployed();

  const MockNft = await ethers.getContractFactory("MockNFT");
  const mockNft = await MockNft.deploy();
  await mockNft.deployed();
  
  await factory.createPool(
    _oracle,
    _maxPrice,
    mockNft.address,
    _maxDailyBorrows,
    _name,
    _symbol,
    _maxLoanLength,
    _maxInterestPerEthPerSecond,
    _minimumInterest,
  );

  const lendingPoolAddress = await factory.allPools(0);
  const LendingPool = await ethers.getContractFactory("LendingPool");
  const lendingPool = await LendingPool.attach(lendingPoolAddress)

  return { factory, lendingPool, mockNft };
}

async function sign(signer, price, deadline, nftContract) {
  const chainId = await signer.getChainId()
  const message = ethers.utils.arrayify("0x" + new ethers.utils.AbiCoder().encode(["uint216", "uint", "uint"], [price, deadline, chainId]).substr(10 + 2) + nftContract.substr(2));
  const signature = ethers.utils.splitSignature(await signer.signMessage(message))
  return signature
}

module.exports = {
  deployAll,
  sign
}