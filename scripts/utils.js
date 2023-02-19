const { ethers } = require("hardhat");

async function deployAll(
  _oracle,
  _maxPrice,
  _maxDailyBorrows,
  _name,
  _symbol,
  _maxLoanLength,
  maxVariableInterestPerEthPerSecond,
  minimumInterest,
  ltv
) {
  const feeCollector = await (await ethers.getContractFactory("FeeCollector")).deploy();
  await feeCollector.deployed();

  const LendingPoolImplementation = await ethers.getContractFactory("LendingPool");
  const lendingPoolImplementation = await LendingPoolImplementation.deploy(feeCollector.address);
  await lendingPoolImplementation.deployed();

  const Factory = await ethers.getContractFactory("LlamaLendFactory");
  const factory = await Factory.deploy(lendingPoolImplementation.address);
  await factory.deployed();

  const MockNft = await ethers.getContractFactory("MockNFT");
  const mockNft = await MockNft.deploy();
  await mockNft.deployed();
  
  await factory.createPool(
    _oracle,
    _maxDailyBorrows,
    _name,
    _symbol,
    [
      {
        maxPrice: _maxPrice,
        maxLoanLength: _maxLoanLength,
        nftContract: mockNft.address,
        maxVariableInterestPerEthPerSecond,
        minimumInterest,
        ltv,
      }
    ]
  );

  const pools = await factory.queryFilter(factory.filters.PoolCreated());
  const lendingPoolAddress = pools[0].args.pool
  const LendingPool = await ethers.getContractFactory("LendingPool");
  const lendingPool = await LendingPool.attach(lendingPoolAddress)

  return { factory, lendingPool, mockNft };
}

async function sign(signer, price, deadline, nftContract, chainId) {
  const message = ethers.utils.arrayify("0x" + new ethers.utils.AbiCoder().encode(["uint216", "uint", "uint"], [price, deadline, chainId]).substr(10 + 2) + nftContract.substr(2));
  const signature = ethers.utils.splitSignature(await signer.signMessage(message))
  return signature
}

module.exports = {
  deployAll,
  sign
}