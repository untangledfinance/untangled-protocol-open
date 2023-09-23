const { artifacts } = require('hardhat');
const { setup } = require('../setup');
const { expect, assert } = require('chai');
const { BigNumber } = require('ethers');

const ONE_DAY = 86400;
const DECIMAL = BigNumber.from(10).pow(18);
describe('NoteTokenFactory', () => {
  let registry;
  let noteTokenFactory;

  before('create fixture', async () => {
    const SecuritizationPool = await ethers.getContractFactory('SecuritizationPool');
    const MintedNormalTGE = await ethers.getContractFactory('MintedNormalTGE');
    const NoteToken = await ethers.getContractFactory('NoteToken');
    const NoteTokenFactory = await ethers.getContractFactory('NoteTokenFactory');
    const Registry = await ethers.getContractFactory('Registry');

    registry = await Registry.new();
    await registry.initialize();
    noteTokenFactory = await NoteTokenFactory.new();
    await noteTokenFactory.initialize(registry.address);
  });

  it('#createToken', async () => {
    const pool = await SecuritizationPool.new();

    const [deployer] = await ethers.getSigners();
    await registry.setSecuritizationManager(deployer.address);
    await noteTokenFactory.createToken(pool.address, 0, 2, 'TOKEN'); // SENIOR
  });

  it('#pauseUnpauseToken', async () => {
    const pool = await SecuritizationPool.new();
    const tx = await noteTokenFactory.createToken(pool.address, 0, 2, 'TOKEN'); // SENIOR

    const tokenAddress = tx.logs.find((x) => x.event == 'TokenCreated').args.token;

    await expect(noteTokenFactory.pauseUnpauseToken(tokenAddress)).to.not.be.reverted;
  });

  it('#pauseAllToken', async () => {
    const pool = await SecuritizationPool.new();
    await noteTokenFactory.createToken(pool.address, 0, 2, 'TOKEN'); // SENIOR
    await expect(noteTokenFactory.pauseAllTokens()).to.not.be.reverted;
  });

  it('#unPauseAllTokens', async () => {
    const pool = await SecuritizationPool.new();
    await noteTokenFactory.createToken(pool.address, 0, 2, 'TOKEN'); // SENIOR
    await expect(noteTokenFactory.unPauseAllTokens()).to.not.be.reverted;
  });
});
