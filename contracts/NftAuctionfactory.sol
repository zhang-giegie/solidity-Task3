// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "./NftAuction.sol";

contract NftAuctionFactory is Ownable {
    // 拍卖合约实现地址
    address public auctionImplementation;
    // 所有创建的拍卖合约
    address[] public allAuctions;
    // NFT到拍卖合约的映射
    mapping(address => mapping(uint256 => address)) public nftToAuction;

    // 事件
    event AuctionCreated(
        address indexed auctionContract,
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller
    );

    constructor(address _auctionImplementation) {
        auctionImplementation = _auctionImplementation;
    }

    /**
     * @dev 创建新的拍卖合约
     * @param _duration 拍卖持续时间
     * @param _startPrice 起拍价
     * @param _nftAddress NFT合约地址
     * @param _tokenId NFT代币ID
     * @return 新创建的拍卖合约地址
     */
    function createAuction(
        uint256 _duration,
        uint256 _startPrice,
        address _nftAddress,
        uint256 _tokenId
    ) external returns (address) {
        // 检查NFT是否已经在拍卖中
        require(
            nftToAuction[_nftAddress][_tokenId] == address(0),
            "NFT is already in auction"
        );

        // 克隆拍卖合约
        address auctionContract = Clones.clone(auctionImplementation);

        // 初始化拍卖合约
        NftAuction(auctionContract).initialize(msg.sender, address(this));

        // 在拍卖合约中创建拍卖
        NftAuction(auctionContract).createAuction(
            _duration,
            _startPrice,
            _nftAddress,
            _tokenId
        );

        // 记录拍卖信息
        allAuctions.push(auctionContract);
        nftToAuction[_nftAddress][_tokenId] = auctionContract;

        emit AuctionCreated(auctionContract, _nftAddress, _tokenId, msg.sender);

        return auctionContract;
    }

    /**
     * @dev 获取所有拍卖合约地址
     * @return 所有拍卖合约地址数组
     */
    function getAllAuctions() external view returns (address[] memory) {
        return allAuctions;
    }

    /**
     * @dev 获取特定NFT的拍卖合约地址
     * @param nftContract NFT合约地址
     * @param tokenId NFT代币ID
     * @return 拍卖合约地址
     */
    function getAuctionForNFT(
        address nftContract,
        uint256 tokenId
    ) external view returns (address) {
        return nftToAuction[nftContract][tokenId];
    }
}
