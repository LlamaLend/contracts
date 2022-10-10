const func = async function (hre) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;
    
    if(process.env.DEPLOY !== "true"){
      throw new Error("DEPLOY env var must be true")
    }
  
    const {deployer} = await getNamedAccounts();
    const LlamaLendImplementationDeployment = await deployments.get('LendingPool');
  
    await deploy('LlamaLendFactory', {
      from: deployer,
      args: [LlamaLendImplementationDeployment.address],
      log: true,
      autoMine: true, // speed up deployment on local network (ganache, hardhat), no effect on live networks
      //deterministicDeployment: true,
    });
  };
  module.exports = func;
  func.tags = ['LlamaLendFactory'];
  func.dependencies = ['LendingPoolImplementation'];