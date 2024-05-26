// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {AggregatorV3Interface} from "@chainlink/contracts@1.1.0/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract TicketGo is Ownable {
    AggregatorV3Interface internal _dataFeed;

    address public immutable nftToken;
    uint256 public concertId;
    mapping(uint256 => Concert) public concertList;
    mapping(address => BuyerInfo[]) public audiencePurchaseInfo;

    struct Concert {
        address concertOwner;
        string concertName;
        string singerName;
        uint256 startSaleTime;
        uint256 endSaleTime;
        uint256 totalBalance;
        Area[] areas;
    }

    struct Area {
        string areaName;
        uint256 seats;
        uint256 price;
    }

    struct BuyerInfo {
        address audienceAddress;
        uint256 concertId;
        string credential;
        string areaName;
        uint256 amount;
        bool winning;
    }

    event EventAddConctract(uint256 indexed concertId, Concert conert);
    event EventAudienceBuyInfo(address indexed audienceAddress, BuyerInfo buyerInfo);
    event EventConcertBought(uint256 indexed concertId, string indexed areaName, address audienceAddress);

    event EventAudienceCanceled(address indexed audienceAddress, BuyerInfo buyerInfo);
    event EvenetConcertCancelBought(uint256 indexed concertId, string indexed areaName, address audienceAddress);

    event EventDispense(address indexed audienceAddress, BuyerInfo buyerInfo);
    event EventRefund(address indexed audienceAddress, BuyerInfo buyerInfo);

    event EventWithdraw(
        uint256 indexed concertId,
        address singerAddress,
        uint256 singerAmount,
        address operatorAddress,
        uint256 operatorAmount
    );

    /**
     * Network: Sepolia
     * Aggregator: ETH/USD
     * Address: 0x694AA1769357215DE4FAC081bf1f309aDC325306
     */
    constructor(address _nftToken) Ownable(msg.sender) {
        nftToken = _nftToken;
        dataFeed = AggregatorV3Interface(0x694AA1769357215DE4FAC081bf1f309aDC325306);
    }

    function concertOf(uint256 _concertId) public view returns (Concert memory) {
        return concertList[_concertId];
    }

    function addConcert(
        string memory _concertName,
        string memory _singerName,
        uint256 _startSaleTime,
        uint256 _endSaleTime,
        Area[] memory _areas
    ) external {
        require(bytes(_concertName).length != 0, "conertName can not be null");
        require(bytes(_singerName).length != 0, "singerName can not be null");
        require(_endSaleTime >= _startSaleTime, "endSaleTime must be greate than startSaleTime");
        uint256 currentConcertId = _useConcertId();
        Concert storage currentConcert = concertList[currentConcertId];
        currentConcert.concertOwner = msg.sender;
        currentConcert.concertName = _concertName;
        currentConcert.singerName = _singerName;
        currentConcert.startSaleTime = _startSaleTime;
        currentConcert.endSaleTime = _endSaleTime;
        for (uint256 i = 0; i < _areas.length; i++) {
            currentConcert.areas.push(_areas[i]);
        }
        emit EventAddConctract(currentConcertId, currentConcert);
    }

    function _useConcertId() internal returns (uint256) {
        return concertId++;
    }

    // function alterIsOnSale(uint256 _concertId) external onlyOwner {
    //     isOnSale[_concertId] = true;
    // }

    function _isExistAreaName(uint256 _concertId, string memory _areaName) internal view returns (bool, uint256) {
        Concert storage concert = concertList[_concertId];
        Area[] storage areas = concert.areas;
        uint256 areaIndex;
        bool isExist = false;
        for (uint256 i = 0; i < areas.length; i++) {
            if (keccak256(abi.encode(areas[i].areaName)) == keccak256(abi.encode(_areaName))) {
                isExist = true;
                areaIndex = i;
            }
        }
        return (isExist, areaIndex);
    }

    /**
     * @dev The user calls this function to paurchase tickets.
     */
    function buy(uint256 _concertId, string memory _credential, string memory _areaName) external payable {
        require(concertList[_concertId].startSaleTime <= block.timestamp, "Sale not start");
        require(block.timestamp <= concertList[_concertId].endSaleTime, "Sale ends");
        (bool isExist, uint256 areaIndex) = _isExistAreaName(_concertId, _areaName);
        require(isExist, "Area dosen't exist");
        require(
            concertList[concertId].areas[areaIndex].price
                <= (msg.value * uint256(getChainlinkDataFeedLatestAnswer())) / 1e8,
            "Not Enough Amount"
        );
        (bool isBought,) = _isPurchase(_concertId, _credential, _areaName);
        require(!isBought, "You already bought");
        BuyerInfo memory buyerinfo = BuyerInfo({
            audienceAddress: msg.sender,
            concertId: _concertId,
            credential: _credential,
            areaName: _areaName,
            amount: msg.value
        });
        audiencePurchaseInfo[msg.sender].push(buyerinfo);
        emit EventAudienceBuyInfo(msg.sender, buyerinfo);
        emit EventConcertBought(_concertId, _areaName, msg.sender);
    }

    function cancelBuy(uint256 _concertId, string memory _credential, string memory _areaName) external {
        require(concertList[_concertId].startSaleTime <= block.timestamp, "Sale not start");
        require(block.timestamp <= concertList[_concertId].endSaleTime, "Sale ends");
        (bool isBought, uint256 boughtIndex) = _isPurchase(_concertId, _credential, _areaName);
        require(isBought, "You have not bought");
        emit EventAudienceCanceled(msg.sender, audiencePurchaseInfo[msg.sender][boughtIndex]);
        _deleteAudiencePurchaseInfo(boughtIndex);
        emit EvenetConcertCancelBought(_concertId, _areaName, msg.sender);
    }

    function _isPurchase(uint256 _concertId, string memory _credential, string memory _areaName)
        internal
        view
        returns (bool, uint256)
    {
        BuyerInfo[] memory buyerinfos = audiencePurchaseInfo[msg.sender];
        uint256 boughtIndex;
        bool isBought;
        for (uint256 i = 0; i < buyerinfos.length; i++) {
            if (
                buyerinfos[i].concertId == _concertId
                    && keccak256(abi.encodePacked(buyerinfos[i].areaName)) == keccak256(abi.encodePacked(_areaName))
                    && keccak256(abi.encodePacked(buyerinfos[i].credential)) == keccak256(abi.encodePacked(_credential))
            ) {
                isBought = true;
                boughtIndex = i;
            }
        }
        return (isBought, boughtIndex);
    }

    function _deleteAudiencePurchaseInfo(uint256 boughtIndex) internal {
        BuyerInfo storage buyerinfo = audiencePurchaseInfo[msg.sender][boughtIndex];
        uint256 buyerinfoLength = audiencePurchaseInfo[msg.sender].length;
        buyerinfo = audiencePurchaseInfo[msg.sender][buyerinfoLength - 1];
        delete audiencePurchaseInfo[msg.sender][buyerinfoLength - 1];
    }

    function dispense(BuyerInfo[] buyerList) public {
        for (uint256 i = 0; i < buyerList.length; i++) {
            nftToken.mint(
                buyerList[i].audienceAddress, buyerList[i].concertId, buyerList[i].credential, buyerList[i].areaName
            );
            emit EventDispense(buyerList[i].audienceAddress, buyerList[i]);
        }
    }

    function refund(BuyerInfo[] buyerList) public payable {
        for (uint256 i = 0; i < buyerList.length; i++) {
            uint256 refundAmount = buyerList[i].amount;
            buyerList[i].amount = 0;
            payable(buyerList[i].audienceAddress).call{value: refundAmount}("");
            emit EventRefund(buyerList[i].audienceAddress, buyerList[i]);
        }
    }

    // Final amount settlement
    function withdraw(uint256 _concertId) public payable onlyOwner {
        Concert storage concertInfo = concertOf(_concertId);
        address singerAddress = concertInfo.concertOwner;
        uint256 totalBalance = concertInfo.totalBalance;
        concertInfo.totalBalance = 0;
        uint256 singerAmount = totalBalance * 0.9;
        uint256 operatorAmount = totalBalance * 0.1;

        payable(singerAddress).call{value: singerAmount}("");
        payable(_owner).call{value: operatorAmount}("");

        emit EventWithdraw(_concertId, singerAddress, singerAmount, _owner, operatorAmount);
    }

    // get leatest price ETH/USD
    function getChainlinkDataFeedLatestAnswer() public view returns (int256) {
        (
            ,
            /* uint80 roundID */
            int256 answer, /*uint startedAt*/ /*uint timeStamp*/ /*uint80 answeredInRound*/
            ,
            ,
        ) = _dataFeed.latestRoundData();
        return answer;
    }
}
