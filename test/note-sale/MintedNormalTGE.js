const { artifacts } = require("hardhat");
const { setup } = require("../setup");
const { expect, assert } = require("chai");
const { BigNumber } = require("ethers");

const SecuritizationPool = artifacts.require('SecuritizationPool');
const MintedNormalTGE = artifacts.require('MintedNormalTGE');
const NoteToken = artifacts.require('NoteToken');


const ONE_DAY = 86400;
const DECIMAL = BigNumber.from(10).pow(18);
describe('MintedNormalTGE', () => {
    let mintedNormalTGE;
    let registry;
    let securitizationPool;

    let snapshotId;

    before('create fixture', async () => {
        snapshotId = await network.provider.send('evm_snapshot');

        const [poolTest] = await ethers.getSigners();
        ({
            registry,
            noteTokenFactory
        } = await setup());

        mintedNormalTGE = await MintedNormalTGE.new();
        securitizationPool = await SecuritizationPool.new();
        const currencyAddress = await securitizationPool.underlyingCurrency();
        const longSale = true;
        const noteToken = await NoteToken.new('Test', 'TST', 18, securitizationPool.address, 1);

        await mintedNormalTGE.initialize(
            registry.address,
            poolTest.address,
            noteToken.address,
            currencyAddress,
            longSale
        );
    });

    after(async () => {
        await network.provider.send("evm_revert", [snapshotId]);
    });

    it('Get isLongSale', async () => {
        assert.equal(await mintedNormalTGE.isLongSale(), true);
    });

    it('Set Yield', async () => {
        await mintedNormalTGE.setYield(20);
        assert.equal(await mintedNormalTGE.yield(), 20);
    });

    it('Setup LongSale', async () => {
        await mintedNormalTGE.setupLongSale(
            20,
            86400,
            Math.trunc(Date.now() / 1000)
        );
    });
});