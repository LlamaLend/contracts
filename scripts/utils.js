const { ethers } = require("hardhat");

async function getContract(name, params){
  const LendingPool = await hre.ethers.getContractFactory(name);
  const lendingPool = await LendingPool.deploy(...params);
  await lendingPool.deployed();
  return {lendingPool}
}

async function sign(signer, price, deadline, nftContract){
    const chainId = await signer.getChainId()
    const message = ethers.utils.arrayify(new ethers.utils.AbiCoder().encode([ "uint", "uint", "uint"], [ price, deadline, chainId ])+nftContract.substr(2));
    const signature = ethers.utils.splitSignature(await signer.signMessage(message))
    return signature
}

module.exports={
    getContract,
    sign
}