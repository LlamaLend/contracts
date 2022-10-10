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

  const chainId = await (await ethers.getSigner()).getChainId()
  const isTestnet = chainId !== 1;

  const params = [
    isTestnet? "0x70997970C51812dc3A010C7d01b50e0d17dc79C8" // Fake oracle
    :"0x4096b3f0e89c06e98d1095da7aefdd4b38eeb1e0", // Real oracle
    "60000000000000000", // 0.06 eth
    isTestnet?
       "0xf5de760f2e916647fd766b4ad9e85ff943ce3a2b"  // MultiFaucet NFT
      :"0xCa7cA7BcC765F77339bE2d648BA53ce9c8a262bD", // tubby cats
    "1000000000000000000", // 1 eth
    "TubbyLoan",
    "TL",
    "1209600", // 2 weeks
    "25367833587", // 80% p.a.
    "12683916793", // 40% p.a.
    "330000000000000000", // 33% LTV
  ]

  const deployResult = await (await factory.createPool(
    ...params,
    {
      from: deployer
    }
  )).wait()

  const poolAddress = deployResult.events[3].args.pool
  log(`contract LendingPool deployed at ${poolAddress}`);
};
module.exports = func;
func.tags = ['LendingPool'];
func.dependencies = ['LlamaLendFactory'];