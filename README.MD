# Untangled Protocol

Untangled is a decentralized lending and liquidity protocol for real world asset collaterals.

## Installing

#### Packages

Run the following to install all package dependencies:

```shell
# Just the first time
npm install
```

## Developing

### Smart Contract Development

All contracts are located under `contracts`

1. Make your changes
2. Write tests, which should be placed under `test`
3. Write great commit messages, and put up your PR!

### Directory structure

[to update]

### Contributing

- See the [`CONTRIBUTING.MD`](./CONTRIBUTING.MD)

### Code of Conduct

- See the [`CODE_OF_CONDUCT.MD`](./CODE_OF_CONDUCT.MD)

### Testing

Run `npm test` to run tests for all contracts.

### Compiling Smart Contracts

```
npm run compile
```

### Deployment

For interactions or contract deployments on public testnets / mainnet, create a .env file specifying your private key and infura api key, with the `.env.example` format.

```
yarn deploy --tags [..] --network [..]
```

`truffle migrate --reset --compile-all --network development`

`npx hardhat run ./deploy/12_deploy_SM.js --network alfajores`

`npx hardhat verify 0x8594888F7617444Ca1baD59fC73a7703783710a5 --network alfajores`

[Document on Verify and Upload](https://docs.google.com/document/d/12tGPUNdDWYi6iyv_Kr7X3eJuNmDZIaosjn9WTEnOXOQ/edit?usp=sharing)
