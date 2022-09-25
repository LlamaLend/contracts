const { ethers } = require("hardhat");

async function deployAll(
  _oracle,
  _maxPrice,
  _nftContract,
  _maxDailyBorrows,
  _name,
  _symbol,
  _maxLoanLength,
  _maxInterestPerEthPerSecond,
) {
  const Factory = await ethers.getContractFactory("LlamaLendFactory");
  const factory = await Factory.deploy();
  await factory.deployed();
  
  await factory.createPool(
    _oracle,
    _maxPrice,
    _nftContract,
    _maxDailyBorrows,
    _name,
    _symbol,
    _maxLoanLength,
    _maxInterestPerEthPerSecond,
  );

  const lendingPoolAddress = await factory.allPools(0);
  const LendingPool = await ethers.getContractFactory("LendingPool");
  const lendingPool = await LendingPool.attach(lendingPoolAddress)

  return { factory, lendingPool };
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