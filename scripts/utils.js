const { ethers } = require("hardhat");

async function getContract(name, params){
  const LendingPool = await hre.ethers.getContractFactory(name);
  const lendingPool = await LendingPool.deploy(...params);
  await lendingPool.deployed();
  return {lendingPool}
}

async function sign(signer, price, deadline, nftContract){
    const message = ethers.utils.arrayify(new ethers.utils.AbiCoder().encode([ "uint", "uint"], [ price, deadline ])+nftContract.substr(2));
    const signature = ethers.utils.splitSignature(await signer.signMessage(message))
    return signature
}

module.exports={
    getContract,
    sign
}