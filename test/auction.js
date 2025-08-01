// 引入 hardhat 和 chai 测试工具
const { ethers, deployments } = require("hardhat")
const { expect } = require("chai")

// 定义测试套件
describe("Test auction", async function () {
    // 定义单个测试用例
    it("Should be ok", async function () {
        // 执行主测试逻辑
        await main();
    });
})

// 主测试逻辑函数
async function main() {
    // 获取测试账户签名者（signer为所有者，buyer为买家）
    const [signer, buyer] = await ethers.getSigners()

    // 部署测试所需的合约（基于部署标签 "depolyNftAuction"）
    await deployments.fixture(["depolyNftAuction"]);

    // 获取代理合约信息
    const nftAuctionProxy = await deployments.get("NftAuctionProxy");

    // 通过代理合约地址获取拍卖合约实例
    const nftAuction = await ethers.getContractAt(
        "NftAuction",
        nftAuctionProxy.address
    );

    // 部署并初始化测试用的ERC20代币合约（模拟USDC）
    const TestERC20 = await ethers.getContractFactory("TestERC20");
    const testERC20 = await TestERC20.deploy();
    await testERC20.waitForDeployment();
    const UsdcAddress = await testERC20.getAddress();

    // 将一部分代币转移给买家用于竞拍
    let tx = await testERC20.connect(signer).transfer(buyer, ethers.parseEther("1000"))
    await tx.wait()

    // 部署并初始化ETH/USD价格预言机（模拟Chainlink）
    const aggreagatorV3 = await ethers.getContractFactory("AggreagatorV3")
    const priceFeedEthDeploy = await aggreagatorV3.deploy(ethers.parseEther("10000"))
    const priceFeedEth = await priceFeedEthDeploy.waitForDeployment()
    const priceFeedEthAddress = await priceFeedEth.getAddress()
    console.log("ethFeed: ", priceFeedEthAddress)

    // 部署并初始化USDC/USD价格预言机
    const priceFeedUSDCDeploy = await aggreagatorV3.deploy(ethers.parseEther("1"))
    const priceFeedUSDC = await priceFeedUSDCDeploy.waitForDeployment()
    const priceFeedUSDCAddress = await priceFeedUSDC.getAddress()
    console.log("usdcFeed: ", await priceFeedUSDCAddress)

    // 构建代币与价格预言机的映射关系
    const token2Usd = [{
        token: ethers.ZeroAddress,       // ETH地址为0地址
        priceFeed: priceFeedEthAddress   // ETH价格预言机地址
    }, {
        token: UsdcAddress,              // USDC代币地址
        priceFeed: priceFeedUSDCAddress  // USDC价格预言机地址
    }]

    // 设置代币价格预言机映射
    for (let i = 0; i < token2Usd.length; i++) {
        const { token, priceFeed } = token2Usd[i];
        await nftAuction.setPriceFeed(token, priceFeed);
    }

    // 1. 部署测试用的ERC721 NFT合约
    const TestERC721 = await ethers.getContractFactory("TestERC721");
    const testERC721 = await TestERC721.deploy();
    await testERC721.waitForDeployment();
    const testERC721Address = await testERC721.getAddress();
    console.log("testERC721Address::", testERC721Address);

    // 2. 为所有者账户铸造10个NFT
    for (let i = 0; i < 10; i++) {
        await testERC721.mint(signer.address, i + 1);
    }

    const tokenId = 1;

    // 授权拍卖代理合约可以操作所有者的所有NFT
    await testERC721.connect(signer).setApprovalForAll(nftAuctionProxy.address, true);

    // 创建拍卖：持续时间10秒，起拍价0.01 ETH，NFT地址和tokenId
    await nftAuction.createAuction(
        10,
        ethers.parseEther("0.01"),
        testERC721Address,
        tokenId
    );

    // 获取创建的拍卖信息
    const auction = await nftAuction.auctions(0);

    console.log("创建拍卖成功：：", auction);

    // 3. 买家参与拍卖
    // 使用ETH竞价
    tx = await nftAuction.connect(buyer).placeBid(0, 0, ethers.ZeroAddress, { value: ethers.parseEther("0.01") });
    await tx.wait()

    // 使用USDC竞价（先授权代币使用）
    tx = await testERC20.connect(buyer).approve(nftAuctionProxy.address, ethers.MaxUint256)
    await tx.wait()
    tx = await nftAuction.connect(buyer).placeBid(0, ethers.parseEther("101"), UsdcAddress);
    await tx.wait()

    // 4. 结束拍卖
    // 等待拍卖时间结束（10秒）
    await new Promise((resolve) => setTimeout(resolve, 10 * 1000));

    // 所有者结束拍卖
    await nftAuction.connect(signer).endAuction(0);

    // 验证拍卖结果
    const auctionResult = await nftAuction.auctions(0);
    console.log("结束拍卖后读取拍卖成功：：", auctionResult);
    expect(auctionResult.highestBidder).to.equal(buyer.address);  // 最高出价者应为买家
    expect(auctionResult.highestBid).to.equal(ethers.parseEther("101")); // 最高出价应为101 USDC

    // 验证NFT所有权已转移给买家
    const owner = await testERC721.ownerOf(tokenId);
    console.log("owner::", owner);
    expect(owner).to.equal(buyer.address);
}