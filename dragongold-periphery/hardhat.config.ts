import 'dotenv/config'
import 'hardhat-typechain'
import '@nomiclabs/hardhat-ethers'
import '@nomiclabs/hardhat-waffle'
import '@nomiclabs/hardhat-etherscan'

const accounts: string[] = process.env.HARDHAT_ACCOUNT_KEY ? [process.env.HARDHAT_ACCOUNT_KEY] : []

export default {
  networks: {
    hardhat: {
      allowUnlimitedContractSize: false,
    },
    hsc: {
      url: 'https://http-mainnet.hoosmartchain.com',
      accounts,
    },
    bsc: {
      url: 'https://bsc-dataseed.binance.org/',
      accounts,
    },
  },
  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  solidity: {
    version: '0.6.6',
    settings: {
      optimizer: {
        enabled: true,
        runs: 800,
      },
    },
  },
}
