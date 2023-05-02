import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  const token = await deploy("SuperBetaToken", {
    from: deployer,
    log: true,
    args: [],
    autoMine: true, // speed up deployment on local network (ganache, hardhat), no effect on live networks
  });

  const youbet = await deploy("SP_Bet", {
    from: deployer,
    log: true,
    args: [token.address],
    autoMine: true, // speed up deployment on local network (ganache, hardhat), no effect on live networks
  });
};

export default func;
func.tags = ["SP_Bet"];
