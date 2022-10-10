const func = async function (hre) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;
    
    if(process.env.DEPLOY !== "true"){
      throw new Error("DEPLOY env var must be true")
    }
  
    const {deployer} = await getNamedAccounts();
  
    await deploy('LendingPool', {
      from: deployer,
      args: [],
      log: true,
      autoMine: true, // speed up deployment on local network (ganache, hardhat), no effect on live networks
      //deterministicDeployment: true,
    });
  };
  module.exports = func;
  func.tags = ['LendingPoolImplementation'];
  