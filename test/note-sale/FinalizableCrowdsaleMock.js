const { artifacts, ethers, upgrades } = require('hardhat');
const { setup } = require('../setup');
const { expect, assert } = require('chai');
const { BigNumber, providers } = require('ethers');
const { keccak256 } = require('@ethersproject/keccak256');

const ONE_DAY = 86400;
const DECIMAL = BigNumber.from(10).pow(18);
describe('FinalizableCrowdsaleMock', () => {
  let registry;
  let securitizationPool;
  let finalizableCrowdSale;

  before('create fixture', async () => {
    ({ registry } = await setup());

    const SecuritizationPool = await ethers.getContractFactory('SecuritizationPool');
    securitizationPool = await SecuritizationPool.deploy();
    const NoteToken = await ethers.getContractFactory('NoteToken');
    const noteToken = await upgrades.deployProxy(NoteToken, ['Test', 'TST', 18, securitizationPool.address, 1], {
      initializer: 'initialize(string,string,uint8,address,uint8)',
    });
    const currencyAddress = await securitizationPool.underlyingCurrency();

    const finalizableCrowdsaleMock = await ethers.getContractFactory('FinalizableCrowdsaleMock');
    finalizableCrowdSale = await finalizableCrowdsaleMock.deploy();
    finalizableCrowdSale.initialize(registry.address, securitizationPool.address, noteToken.address, currencyAddress);
  });

  it('#finalize', async () => {
    const [signer] = await ethers.getSigners();
    await finalizableCrowdSale.grantRole(keccak256(Buffer.from('OWNER_ROLE')), signer.address);

    await finalizableCrowdSale.connect(signer).finalize(false, signer.address);
  });
});
