const { artifacts, ethers } = require('hardhat');
const { setup } = require('../setup');
const { expect, assert } = require('chai');
const { BigNumber, providers } = require('ethers');
const { keccak256 } = require('@ethersproject/keccak256');
const { impersonateAccount, setBalance } = require('@nomicfoundation/hardhat-network-helpers');

const ONE_DAY = 86400;
const DECIMAL = BigNumber.from(10).pow(18);
describe('FinalizableCrowdsaleMock', () => {
  let registry;
  let securitizationPool;
  let finalizableCrowdSale;

  before('create fixture', async () => {
    ({ registry, noteTokenFactory } = await setup());

    const SecuritizationPool = await ethers.getContractFactory('SecuritizationPool');
    securitizationPool = await SecuritizationPool.deploy();
    const NoteToken = await ethers.getContractFactory('NoteToken');
    const noteToken = await NoteToken.deploy('Test', 'TST', 18, securitizationPool.address, 1);
    const currencyAddress = await securitizationPool.underlyingCurrency();

    const finalizableCrowdsaleMock = await ethers.getContractFactory('FinalizableCrowdsaleMock');
    finalizableCrowdSale = await finalizableCrowdsaleMock.deploy();
    finalizableCrowdSale.initialize(registry.address, securitizationPool.address, noteToken.address, currencyAddress);

    // ({ registry, noteTokenFactory } = await setup());

    // securitizationPool = await SecuritizationPool.deploy();
    // const noteToken = await NoteToken.deploy('Test', 'TST', 18, securitizationPool.address, 1);
    // const currencyAddress = await securitizationPool.underlyingCurrency();

    // const TimedCrowdsaleMock = await ethers.getContractFactory('TimedCrowdsaleMock');
    // timedCrowdsale = await TimedCrowdsaleMock.deploy();
    // timedCrowdsale.initialize(registry.address, securitizationPool.address, noteToken.address, currencyAddress);
  });

  it('#finalize', async () => {
    await impersonateAccount(securitizationPool.address);
    await setBalance(securitizationPool.address, ethers.utils.parseEther('1'));
    const signer = await ethers.getSigner(securitizationPool.address);

    await finalizableCrowdSale.connect(signer).finalize(false, signer.address);
  });
});
