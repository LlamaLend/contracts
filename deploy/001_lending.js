/*
const func = async function (hre) {
  const {deployments, getNamedAccounts} = hre;
  const {deploy} = deployments;
  
  if(process.env.DEPLOY !== "true"){
    throw new Error("DEPLOY env var must be true")
  }

  const {deployer} = await getNamedAccounts();

  await deploy('LendingPool', {
    from: deployer,
    args: [
      "0x4096b3f0e89c06e98d1095da7aefdd4b38eeb1e0",
      "60000000000000000", // 0.06 eth
      "0xCa7cA7BcC765F77339bE2d648BA53ce9c8a262bD", // tubby cats
      "1000000000000000000", // 1 eth
      "TubbyLoan",
      "TL",
      "1209600", // 2 weeks
      "25367833587", // 80% p.a.
    ],
    log: true,
    autoMine: true, // speed up deployment on local network (ganache, hardhat), no effect on live networks
    //deterministicDeployment: true,
  });
};
module.exports = func;
func.tags = ['LendingPool'];
func.dependencies = ['LlamaLendFactory'];
*/