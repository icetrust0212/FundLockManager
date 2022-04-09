import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { Contract } from "ethers";
import { ethers, getNamedAccounts,  } from "hardhat";
import ERC20ABI from '../data/ERC20';

let fundLockManager: Contract;
let _signer: SignerWithAddress;
let _fundOwner: SignerWithAddress;
let _unlocker: SignerWithAddress;
let _other: SignerWithAddress;
let denominationERC20: Contract;
let usdcContract: Contract;
let usdcWhale: SignerWithAddress;

const denominationTokenAddress = "0xdAC17F958D2ee523a2206206994597C13D831ec7"; // Mainnet USDT address
const USDC_ADDRESS = "0x6262998ced04146fa42253a5c0af90ca02dfd2a3"; //mainnet USDC address;
const USDC_WHALE_ADDRESS = "0x1d42064Fc4Beb5F8aAF85F4617AE8b3b5B8Bd801" // mainnet usdc whale;

const lockTime = 365 * 24 * 3600; // 1 year lock

describe("FundLockManager", function () {
  beforeEach(async () => {
    const contractFactory = await ethers.getContractFactory("FundLockManager"); 
    fundLockManager = await contractFactory.deploy(denominationTokenAddress);
    await fundLockManager.deployed();
    
    denominationERC20 = new ethers.Contract(denominationTokenAddress, ERC20ABI, ethers.provider);
    usdcContract = new ethers.Contract(USDC_ADDRESS, ERC20ABI, ethers.provider);

    const {deployer, fundOwner, unlocker, other} = await getNamedAccounts();
    _signer = await ethers.getSigner(deployer);
    _fundOwner = await ethers.getSigner(fundOwner);
    _unlocker = await ethers.getSigner(unlocker);
    _other = await ethers.getSigner(other);
    usdcWhale = await ethers.getSigner(USDC_WHALE_ADDRESS);
  })

  it("Check deploy: ", async function () {
    expect(await fundLockManager.owner()).to.equal(_signer.address);
  });

  it("Check eth => usdt swap function on uniswap: ", async () => {
    expect(await denominationERC20.balanceOf(fundLockManager.address)).to.be.equal(0);
    
    //Send eth to fundLockManager, swap
    await fundLockManager.connect(_fundOwner).LockEthWithSwapToken(_unlocker.address, lockTime, {
      value: ethers.utils.parseEther("1")
    } );

    // check if eth was swapped with usdt
    expect(await denominationERC20.balanceOf(fundLockManager.address)).to.above(0);
    // check if fundLockManager's eth balance is 0 after swap
    expect(await ethers.provider.getBalance(fundLockManager.address)).to.be.equal(0);
  });

  it("Check anytoken => eth swap function on uniswap: ", async () => {
    expect(await denominationERC20.balanceOf(fundLockManager.address)).to.be.equal(0);
    
    //Send 1 usdc to fundLockManager, swap
    await fundLockManager.connect(usdcWhale).LockTokenWithSwapToken(USDC_ADDRESS, ethers.utils.parseEther("1"), _unlocker.address, lockTime);

    // check if usdc was swapped with usdt
    expect(await denominationERC20.balanceOf(fundLockManager.address)).to.above(0);
    // check if fundLockManager's usdc balance is 0 after swap
    expect(await usdcContract.balanceOf(fundLockManager.address)).to.equal(0);
  });

  it("Check whitelist mint: ", async () => {
 
    // await expect(nftContract.mintWhitelistSale(_signer.address, proof, 1)).to.be.revertedWith("Not whitelisted");
  });
});
