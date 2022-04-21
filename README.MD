# Untangled Protocol
Untangled is a decentralized lending and liquidity protocol for real world asset collaterals. 

## Installing
#### Node version

You will need the correct version of node/npm on your local machine.

Using nvm, you can do this with `nvm install 12.18.3`. If you don't have `nvm`, see [here](https://github.com/nvm-sh/nvm#installing-and-updating) for installation instructions.

## Developing

### Smart Contract Development
All contracts are located under `packages/protocol/contracts`
1. Make your changes
2. Write tests, which should be placed under `packages/protocol/test`
    - There are two kinds of tests. "Regular" (all local state) and "mainnet forking" (uses state from mainnet). They are located in different folders. Sometimes you write both for the same feature. Use your judgement depending on the change.
3. Write great commit messages, and put up your PR!

### Contributing
- See the [`CONTRIBUTING.MD`](./CONTRIBUTING.MD)

### Code of Conduct
- See the [`CODE_OF_CONDUCT.MD`](./CODE_OF_CONDUCT.MD)

### Testing
[to update]

### Compiling Smart Contracts
Generally speaking, you shouldn't need to do this, since the test command automatically compiles. But if you need to independently compile, you can run:

```
npm run build
```

This will run `npm run build` in all packages in the monorepo, including compiling the contracts.


### Deployment
#### Local deployment
Contract deployment is handled automatically through the `npm run start` command, using [hardhat-deploy](https://github.com/wighawag/hardhat-deploy) and
custom build scripts in `packages/protocol/blockchain_scripts`.

#### Testnet deployments

#### Mainnet deployments:

When contracts are deployed to mainnet. we write custom scripts to do upgrades or deploy new contracts.

