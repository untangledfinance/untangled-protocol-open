# Untangled Protocol
Untangled is a decentralized lending and liquidity protocol for real world asset collaterals. 

## Installing
#### Node version

You will need the correct version of node/npm on your local machine.

Using nvm, you can do this with `nvm install 12.18.3`. If you don't have `nvm`, see [here](https://github.com/nvm-sh/nvm#installing-and-updating) for installation instructions.

#### Packages

The repository is organized as a monorepo using [lerna](https://lerna.js.org/). Run the following to install lerna and then use it to install all package dependencies:

```shell
# Just the first time
npm install
npm run bootstrap
```

From here on out, every time you pull the repo and any packages change, you'll need to run

```shell
npm install
# Note use lerna bootstrap, and not npm run bootstrap. It's much faster
npx lerna bootstrap
```

## Developing

### Smart Contract Development
All contracts are located under `packages/protocol/contracts`
1. Make your changes
2. Write tests, which should be placed under `packages/protocol/test`
    - There are two kinds of tests. "Regular" (all local state) and "mainnet forking" (uses state from mainnet). They are located in different folders. Sometimes you write both for the same feature. Use your judgement depending on the change.
3. Write great commit messages, and put up your PR!


#### Other ways to run
* `npm run start:no-gasless` is available if gasless transactions are giving you trouble, or if you're having trouble finding the borrower contract address.

### Directory structure
[to update]

### Tenderly debugging
[To update]
We have the ability to debug/profile local transactions via [Tenderly](Tenderly.co). To do this, get hold of a transaction hash and then run:

```bash
# Ensure tenderly-cli is installed via `brew tap tenderly/tenderly && brew install tenderly`
# And run this from the protocol directory
tenderly export --force <txhash>
```

To get a local transaction, run the app as normal, and make the transaction via the frontend, and get the hash from metamask after it's confirmed.

To get a test transaction, write a MainnetForking test, log the transaction hash in the test. Then run the mainnet forking test via:

```
# Run from the protocol directory
npm run test:tenderly
```

Pick up the transaction hash from the output of the test and run export as above

### Contributing
- See the [`CONTRIBUTING.MD`](./CONTRIBUTING.MD)

### Code of Conduct
- See the [`CODE_OF_CONDUCT.MD`](./CODE_OF_CONDUCT.MD)

### Gasless transactions

### Testing
- Run `npm test` to run tests for all packages.
- Note if you want to only run tests for a particular test, then use `it.only` or `describe.only` inside the test file itself, which will focus to only those tests.
- If you want to run tests for a specific package, say just the protocol contracts, you can use lerna's `--scope` flag e.g. `npm run test -- --scope @goldfinch-eng/protocol`.

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

