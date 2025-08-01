require("@nomicfoundation/hardhat-toolbox");
require("hardhat-deploy"); // 添加这一行来引入 hardhat-deploy 插件
require("@openzeppelin/hardhat-upgrades")

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.28",
  namedAccounts: {
    deployer: {
      default: 0,
    },
    user1: {
      default: 1,
    },
    user2: {
      default: 2,
    },
  },
  networks: {
    hardhat: {
      chainId: 31337,
    },
  },
};