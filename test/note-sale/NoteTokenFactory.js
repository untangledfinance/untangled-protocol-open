

const { artifacts } = require("hardhat");
const { setup } = require("../setup");
const { expect, assert } = require("chai");
const { BigNumber } = require("ethers");

const SecuritizationPool = artifacts.require('SecuritizationPool');
const MintedNormalTGE = artifacts.require('MintedNormalTGE');
const NoteToken = artifacts.require('NoteToken');
const NoteTokenFactory = artifacts.require('NoteTokenFactory');
const Registry = artifacts.require('Registry');


const ONE_DAY = 86400;
const DECIMAL = BigNumber.from(10).pow(18);
describe('MintedNormalTGE', () => {
    let registry;
    let noteTokenFactory;

    before('create fixture', async () => {
        registry = await Registry.new();
        await registry.initialize();
        noteTokenFactory = await NoteTokenFactory.new();
        await noteTokenFactory.initialize(registry.address);
    });

    it('#createToken', async () => {
        const pool = await SecuritizationPool.new();

        const [deployer] = await ethers.getSigners();
        await registry.setSecuritizationManager(deployer.address);


        const tx = await noteTokenFactory.createToken(pool.address, 0, 2, "TOKEN"); // SENIOR
        expect(tx).to.be.emit(noteTokenFactory, 'TokenCreated').withArgs(pool.address, 0, 2, "TOKEN");
    });

});