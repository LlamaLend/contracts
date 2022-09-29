const func = async function (hre) {
  const {deployments, getNamedAccounts, ethers} = hre;
  const {deployIfDifferent, log} = deployments;
  
  if(process.env.DEPLOY !== "true"){
    throw new Error("DEPLOY env var must be true")
  }

  const {deployer} = await getNamedAccounts();

  const LlamaLendFactoryDeployment = await deployments.get('LlamaLendFactory');
  const LlamaLendFactory = await ethers.getContractFactory("LlamaLendFactory");
  const factory = await LlamaLendFactory.attach(LlamaLendFactoryDeployment.address)

  const deployResult = await (await factory.createPool(
    "0x4096b3f0e89c06e98d1095da7aefdd4b38eeb1e0",
    "60000000000000000", // 0.06 eth
    "0xCa7cA7BcC765F77339bE2d648BA53ce9c8a262bD", // tubby cats
    "1000000000000000000", // 1 eth
    "TubbyLoan",
    "TL",
    "1209600", // 2 weeks
    "25367833587", // 80% p.a.
    "12683916793", // 40% p.a.
    {
      from: deployer
  })).wait()

  log(`contract LendingPool deployed at ${deployResult.events[2].args.pool}`);
};
module.exports = func;
func.tags = ['LendingPool'];
func.dependencies = ['LlamaLendFactory'];