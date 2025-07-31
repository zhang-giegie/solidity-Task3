// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "hardhat/console.sol";

contract NftAuction is Initializable, UUPSUpgradeable {
    //结构体
    struct Auction {
        //拍卖者
        address seller;
        //拍卖时长
        uint256 duration;
        //开始价格
        uint256 startPrice;
        //开始时间
        uint256 startTime;
        //拍卖是否结束
        bool ended;
        //最高出价者
        address highestBidder;
        //最高出价
        uint256 highestBid;
        // NFT合约地址
        address nftContract;
        //NFT的id
        uint256 tokenId;
        //参与竞价的资产类型
        //0：ETH 其他表示erc20
        address tokenAddress;
    }

    //状态变量
    mapping(uint256 => Auction) public auctions;
    // 下一个拍卖id
    uint256 public nextAuctionId;
    //管理员地址
    address public admin;
    //工厂合约地址
    address public factory;

    mapping(address => AggregatorV3Interface) public priceFeeds;

    // 添加接收ETH的函数
    receive() external payable {}

    // 修饰符，只允许工厂合约调用
    modifier onlyFactory() {
        require(msg.sender == factory, "Only factory can call this function");
        _;
    }

    function initialize(address _admin, address _factory) public initializer {
        admin = _admin;
        factory = _factory;
    }

    function setPriiceETHFeed(
        address tokenAddress,
        address _priceETHFeed
    ) public {
        priceFeeds[tokenAddress] = AggregatorV3Interface(_priceETHFeed);
    }

    function getChainlinkDataFeedLatestAnswer(
        address tokenAddress
    ) public view returns (int) {
        AggregatorV3Interface priceFeed = priceFeeds[tokenAddress];

        // prettier-ignore
        (
            /* uint80 roundId */,
            int256 answer,
            /*uint256 startedAt*/,
            /*uint256 updatedAt*/,
            /*uint80 answeredInRound*/
        ) = priceFeed.latestRoundData();
        return answer;
    }

    //创建拍卖
    function createAuction(
        uint256 _duration,
        uint256 _startPrice,
        address _nftAddress,
        uint256 _tokenId
    ) public onlyFactory {
        //允许任何用户创建拍卖
        //参数检查
        require(_duration >= 10, "Duration must be at least 10 seconds.");
        require(_startPrice > 0, "Start price must be greater than 0.");

        //转移NFT到合约
        IERC721(_nftAddress).transferFrom(msg.sender, address(this), _tokenId);

        auctions[nextAuctionId] = Auction({
            seller: msg.sender,
            duration: _duration,
            startPrice: _startPrice,
            startTime: block.timestamp,
            ended: false,
            highestBidder: address(0),
            highestBid: 0,
            nftContract: _nftAddress,
            tokenId: _tokenId,
            tokenAddress: address(0)
        });
        nextAuctionId++;
    }

    // 买家参与买单
    function placeBid(
        uint256 _auctionId,
        uint256 amount,
        address _tokenAddress
    ) external payable {
        Auction storage auction = auctions[_auctionId];
        //判断当前拍卖是否结束
        require(
            !auction.ended &&
                auction.startTime + auction.duration > block.timestamp,
            "Auction has ended."
        );

        uint payValue;
        uint256 actualAmount = amount;

        if (_tokenAddress != address(0)) {
            //处理ERC20
            require(
                msg.value == 0,
                "No ETH should be sent when bidding with ERC20"
            );
            payValue =
                actualAmount *
                uint(getChainlinkDataFeedLatestAnswer(_tokenAddress));
        } else {
            //处理ETH
            actualAmount = msg.value;
            require(amount == 0, "Amount should be 0 when bidding with ETH");
            payValue =
                actualAmount *
                uint(getChainlinkDataFeedLatestAnswer(address(0)));
        }

        uint startPriceValue = auction.startPrice *
            uint(getChainlinkDataFeedLatestAnswer(_tokenAddress));
        uint highestBidValue = auction.highestBid *
            uint(getChainlinkDataFeedLatestAnswer(auction.tokenAddress));

        //判断当前价格是否满足要求
        require(
            payValue >= startPriceValue && payValue > highestBidValue,
            "Bid must be higher than the start price and current highest bid."
        );

        // 处理新出价的转账
        if (_tokenAddress != address(0)) {
            IERC20(_tokenAddress).transferFrom(
                msg.sender,
                address(this),
                actualAmount
            );
        }

        // 退回之前的最高出价
        if (auction.highestBidder != address(0)) {
            if (auction.tokenAddress == address(0)) {
                payable(auction.highestBidder).transfer(auction.highestBid);
            } else {
                IERC20(auction.tokenAddress).transfer(
                    auction.highestBidder,
                    auction.highestBid
                );
            }
        }

        auction.tokenAddress = _tokenAddress;
        auction.highestBid = actualAmount;
        auction.highestBidder = msg.sender;
    }

    //结束拍卖
    function endAuction(uint256 _auctionId) external {
        Auction storage auction = auctions[_auctionId];
        //判断是否拍卖结束
        require(
            !auction.ended &&
                auction.startTime + auction.duration <= block.timestamp,
            "Auction has not ended yet."
        );

        // 标记拍卖结束
        auction.ended = true;

        if (auction.highestBidder != address(0)) {
            //转移NFT到最高出价者
            IERC721(auction.nftContract).safeTransferFrom(
                address(this),
                auction.highestBidder,
                auction.tokenId
            );

            //转移资金到卖家
            if (auction.tokenAddress == address(0)) {
                // ETH支付
                payable(auction.seller).transfer(auction.highestBid);
            } else {
                // ERC20支付
                IERC20(auction.tokenAddress).transfer(
                    auction.seller,
                    auction.highestBid
                );
            }
        } else {
            // 没有出价，退回NFT给卖家
            IERC721(auction.nftContract).safeTransferFrom(
                address(this),
                auction.seller,
                auction.tokenId
            );
        }
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal view override {
        require(msg.sender == admin, "Only admin can upgrade the contract.");
    }
}
