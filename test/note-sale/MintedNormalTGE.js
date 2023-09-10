const { artifacts } = require("hardhat");
const { setup } = require("../setup");
const { expect, assert } = require("chai");

const SecuritizationPool = artifacts.require('SecuritizationPool');
const MintedNormalTGE = artifacts.require('MintedNormalTGE');
const NoteToken = artifacts.require('NoteToken');

describe('MintedNormalTGE', () => {
    let mintedNormalTGE;
    let registry;

    before('create fixture', async () => {
        ({
            registry,
            noteTokenFactory
        } = await setup());

        mintedNormalTGE = await MintedNormalTGE.new();
        const securitizationPool = await SecuritizationPool.new();
        const currencyAddress = await securitizationPool.underlyingCurrency();
        const longSale = true;
        const noteToken = await NoteToken.new('Test', 'TST', 18, securitizationPool.address, 1);

        await mintedNormalTGE.initialize(
            registry.address,
            securitizationPool.address,
            noteToken.address,
            currencyAddress,
            longSale
        );
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