const { ethers } = require("hardhat");

async function getContract(name, params){
  const LendingPool = await hre.ethers.getContractFactory(name);
  const lendingPool = await LendingPool.deploy(...params);
  await lendingPool.deployed();
  return {lendingPool}
}

async function sign(signer, price, deadline, nftContract){
    const chainId = await signer.getChainId()
    const message = ethers.utils.arrayify("0x"+new ethers.utils.AbiCoder().encode([ "uint216", "uint", "uint"], [ price, deadline, chainId ]).substr(10+2)+nftContract.substr(2));
    const signature = ethers.utils.splitSignature(await signer.signMessage(message))
    return signature
}

module.exports={
    getContract,
    sign
}