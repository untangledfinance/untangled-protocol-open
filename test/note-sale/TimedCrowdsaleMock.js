const { artifacts } = require("hardhat");
const { setup } = require("../setup");
const { expect, assert } = require("chai");
const { BigNumber } = require("ethers");

const SecuritizationPool = artifacts.require('SecuritizationPool');
const NoteToken = artifacts.require('NoteToken');


const ONE_DAY = 86400;
const DECIMAL = BigNumber.from(10).pow(18);
describe('TimedCrowdsale', () => {
    let registry;
    let securitizationPool;
    let timedCrowdsale;

    before('create fixture', async () => {
        ({
            registry,
            noteTokenFactory
        } = await setup());

        securitizationPool = await SecuritizationPool.new();
        const noteToken = await NoteToken.new('Test', 'TST', 18, securitizationPool.address, 1);
        const currencyAddress = await securitizationPool.underlyingCurrency();

        const TimedCrowdsaleMock = await ethers.getContractFactory('TimedCrowdsaleMock');
        timedCrowdsale = await TimedCrowdsaleMock.deploy();
        timedCrowdsale.initialize(
            registry.address,
            securitizationPool.address,
            noteToken.address,
            currencyAddress
        );
    });

    it('#newSaleRoundTime', async () => {
        const [,, anotherGuy] = await ethers.getSigners();
        await expect(timedCrowdsale.connect(anotherGuy).newSaleRoundTime(0,10)).to.be.revertedWith("Crowdsale: Caller must be owner or pool");
    });

    it('#setUsingTimeLimit', async () => {
        await timedCrowdsale.setUsingTimeLimit(false);
        expect(await timedCrowdsale.isEnableTimeLimit()).to.be.false;
    });
});