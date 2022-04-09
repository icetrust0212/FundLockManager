import { DeployFunction } from 'hardhat-deploy/types';
import { calculate_whitelist_root } from '../whitelist/utils';

const fn: DeployFunction = async function ({ deployments: { deploy }, ethers: { getSigners }, network }) {
  const deployer = (await getSigners())[0];

  const denominationTokenAddress = "0xdAC17F958D2ee523a2206206994597C13D831ec7"; // Mainnet USDT address

  const contractDeployed = await deploy('FundLockManager', {
    from: deployer.address,
    log: true,
    skipIfAlreadyDeployed: true,
    args: [
      denominationTokenAddress
    ]
  });
  console.log('npx hardhat verify --network '+ network.name +  ' ' + contractDeployed.address);

};
fn.skip = async (hre) => {
  // Skip this on kovan.
  const chain = parseInt(await hre.getChainId());
  return chain !== 31337;
};
fn.tags = ['FundLockManager'];

export default fn;
