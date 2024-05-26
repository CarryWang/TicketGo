// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {AggregatorV3Interface} from "@chainlink/contracts@1.1.0/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
// import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./NFT.sol";

contract TicketGo is Ownable VRFConsumerBaseV2 AutomationCompatibleInterface{    
    // Chainlink VRF Variables
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    uint64 private immutable i_subscriptionId;
    bytes32 private immutable i_gasLane;
    uint32 private immutable i_callbackGasLimit;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;

    AggregatorV3Interface internal _dataFeed;

    address private _operator;
    address public immutable nftToken;
    uint8 private withdrawPercent = 9
    uint256 public concertId;

    mapping(uint256 => Concert) public concertList;
    mapping(address => BuyerInfo[]) public audiencePurchaseInfo;
    uint256 internal immutable _a=1664525;
    uint256 internal immutable _c=1013904223;
    uint256 internal immutable _m=2**32;
    
    //{
    //     concertID: {areaName: [BuyerInfo]}
    // }
    mapping(uint256 => mapping(string => BuyerInfo[])) bookingPool;
    // bookingPoolMap helper
    // {
    //     concertID: {areaName: {userAddr: buyerAreaIndex}}
    // }
    mapping(uint256 => mapping(string => mapping(address => uint256))) bookingAreaPoolIndex;

    struct Concert {
        address concertOwner;
        string concertName;
        string singerName;
        uint256 startSaleTime;
        uint256 endSaleTime;
        uint256 showTime;
        uint256 totalBalance;
        Area[] areas;
        bool withdrawed;
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

    event AreaBookingSelected(uint256 indexed concerId, string concertName, uint256[] selectedBookingAddress);
    event ConcertSelected(uint256 indexed concerId);
    event EvenetConcertCancelBought(uint256 indexed concertId, string indexed areaName, address audienceAddress);

    event EventDispense(address indexed audienceAddress, BuyerInfo buyerInfo);
    event EventRefund(address indexed audienceAddress, bool isSuccessFul, BuyerInfo buyerInfo);

    event EventWithdraw(
        uint256 indexed concertId,
        bool singerSuccess,
        address singerAddress,
        uint256 singerAmount,
        bool operatorSuccess,
        address operatorAddress,
        uint256 operatorAmount
    );

    /**
     * Network: Sepolia
     * Aggregator: ETH/USD
     * Address: 0x694AA1769357215DE4FAC081bf1f309aDC325306
     */
    constructor(address vrfCoordinatorV2, uint256 _nftToken) Ownable(msg.sender) VRFConsumerBaseV2(vrfCoordinatorV2){
        nftToken = _nftToken;
        dataFeed = AggregatorV3Interface(0x694AA1769357215DE4FAC081bf1f309aDC325306);
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorV2);

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
        require(bookingAreaPoolIndex[_concertId][_areaName] == 0, "Already booking this Area")
        (bool isBought,) = _isPurchase(_concertId, _credential, _areaName);
        require(!isBought, "You already bought");
        BuyerInfo memory buyerinfo = BuyerInfo({
            audienceAddress: msg.sender,
            concertId: _concertId,
            credential: _credential,
            areaName: _areaName,
            amount: msg.value,
            winning: false
        });
        audiencePurchaseInfo[msg.sender].push(buyerinfo);
        _addBooking(buyerinfo);
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

    function _addBooking(BuyerInfo buyerInfo) internal{
        uint256 cid = buyerinfo.concerId;
        string aname = buyerinfo.areaName;

        bookingPool[cid][aname].push(buyerinfo);
        uint256 buyerAreaIndex = bookingPool[cid][aname].length;
        bookingAreaPoolIndex[cid][aname][msg.sender] = buyerAreaIndex;
    }
    function _deleteBooking(BuyerInfo buyerinfo) internal{
        uint256 cid = buyerinfo.concerId;
        string aname = buyerinfo.areaName;

        uint256 buyerAreaIndex = bookingAreaPoolIndex[cid][aname][msg.sender] - 1;

        delete bookingPool[cid][aname][buyerAreaIndex];
        delete bookingAreaPoolIndex[cid][aname][msg.sender];

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
        _deleteBooking(buyerinfo);
    }

    function dispense(BuyerInfo[] memory buyerList) public {
        for (uint256 i = 0; i < buyerList.length; i++) {
            TicketGoNFT(nftToken).mint(
                buyerList[i].audienceAddress, buyerList[i].concertId, buyerList[i].credential, buyerList[i].areaName
            );
            emit EventDispense(buyerList[i].audienceAddress, buyerList[i]);
        }
    }

function singleRefund(BuyerInfo memory buyerInfo) public payable {
        uint256 refundAmount = buyerInfo.amount;
        buyerInfo.amount = 0;
        (bool success,) = payable(buyerInfo.audienceAddress).call{value: refundAmount}("");
        emit EventRefund(buyerInfo.audienceAddress, success, buyerInfo);
    }

    function refund(BuyerInfo[] memory buyerList) public payable {
        for (uint256 i = 0; i < buyerList.length; i++) {
            singleRefund(buyerList[i]);
        }
    }

    // Final amount settlement
    function withdraw(uint256 _concertId) public payable onlyOwner {
        Concert memory concertInfo = concertOf(_concertId);
        address singerAddress = concertInfo.concertOwner;
        uint256 totalBalance = concertInfo.totalBalance;
        concertInfo.totalBalance = 0;
        uint256 singerAmount = (totalBalance * 90) / 100;
        uint256 operatorAmount = (totalBalance * 10) / 100;

        (bool singerSuccess,) = payable(singerAddress).call{value: singerAmount}("");
        (bool operatorSuccess,) = payable(_operator).call{value: operatorAmount}("");

        emit EventWithdraw(
            _concertId, singerSuccess, singerAddress, singerAmount, operatorSuccess, _operator, operatorAmount
        );
    }

// --------------------------- Chainlink ---------------------
    // this function should be call by Automation.
    // we can call it with a fixed Automation schedule, eg 00:00:00
    // so we choice the final luck user at fix datetime.
    // it's a tradeoff solution
    function performUpkeep(bytes calldata /* performData */) external override {
        checkBookPool();
    }

    function checkBookPool() internal {
        for(uint i = 0; i < concertID; i++){
            Concert concert = concertList[i];
            if (concert.startSaleTime < block.timestamp && concert.endSaleTime > block.timestamp){
                bookPoolSelect(concert);
            }
            bool singerWithdrawTimeCheck = concert.showTime + 3 > block.timestamp;
            bool singerWithdrawStatusCheck = concert.withdrawed == false;
            if (singerWithdrawTimeCheck && singerWithdrawStatusCheck){
                withdraw(i);
            }
        }
    }

    function bookPoolSelect(Concert concert) internal{
        uint8 randomWordsCount = concert.Area.length;

        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            randomWordsCount // request same number as areas, use for draw in each area pool
        );
        vrfRequestParamMap[requestId] = concert.concerId;
    }
    /**
     * @dev This is the function that Chainlink VRF node
     * calls choice final booking.
     */
    function fulfillRandomWords(
        uint256 requestId ,
        uint256[] memory randomWords
    ) internal override {
        uint256 _concertId = vrfRequestParamMap[requestId];
        Concert concert = concertList[_concerId];
        (BuyerInfo[] fortuneBuys, BuyerInfo[] unfortuneBuys) = drawConcert(concert, randomWords);
        processDrawResult(fortuneBuys, unfortuneBuys);
    } 

    function processDrawResult(BuyerInfo[] fortuneBuys, BuyerInfo[] unfortuneBuys) internal {
        generateNFT(fortuneBuys);
        refund(unfortuneBuys);
    }

    function drawConcert(Concert concert, uint[] randomWrods
    ) internal returns (BuyerInfo[], BuyerInfo[]){
        BuyerInfo[] c_fortuneBuys;
        BuyerInfo[] c_unfortuneBuys;

        for(uint i = 0; i < concert.Area.length; i++){
            randomWord = randomWords[i];
            Area area = concert.Area[i];
            BuyerInfo[] areaPool = bookingPool[concerId][area.areaName];
            (BuyerInfo[] fortuneBuys, BuyerInfo[] unfortuneBuys) = drawForAreaPool(areaPool, area.seats, randomWord);
            // concat all buyInfo of
            for(uint i = 0; i < fortuneBuys.length; i++){
                c_fortuneBuys.push(fortuneBuys[i]);
            }
            for(uint i = 0; i < unfortuneBuys.length; i++){
                c_unfortuneBuys.push(unfortuneBuys[i]);
            }
            // for(uint i = c_fortuneBuys.length; i < c_fortuneBuys.length + fortuneBuys.length; i++){
            //     c_fortuneBuys[i] = fortuneBuys;
            // }
            // for(uint i = c_unfortuneBuys.length; i < c_unfortuneBuys.length + unfortuneBuys.length; i++){
            //     c_unfortuneBuys[i] = fortuneBuys;
            // }

        }

        return (c_fortuneBuys, c_unfortuneBuys);
    }
    
    function drawForAreaPool(
        BuyerInfo[] areaPool,  uint256 avaiableNum, uint256 _seed
    ) internal returns(BuyerInfo[], BuyerInfo[]) {

        BuyerInfo[] fortuneBuys;
        BuyerInfo[] unfortuneBuys;

        uint256[] selectedIndexList = drawAreaPoolIndex(areaPool.length, avaiableNum, _seed);
        for(uint areaIdx = 0; areaIdx < areaPool.length; areaIdx++){
            bool selected = false;
            for(uint selectedIdx = 0; j < selectedIdxList.length; selectedIdx++){
                if (areaIdx == selectedIdx){
                    selected = true;
                    break;
                }
            }
            if (selected){
                fortuneBuys.push(areaPool[areaIdx]);
            } else {
                unfortuneBuys.push(areaPool[areaIdx]);
            }
        return (fortuneBuys, unfortuneBuys);
    }

    function drawAreaPoolIndex(uint256 totalNum, uint256 avaiableNum, uint256 _seed) internal returns (uint256[]){
        uint256 seed = _seed;
        uint256[] memory selectedIdxList = new uint256[];
        while (i < avaiableNum){
            idx = seed % avaiableNum;
            selectedIdxList[i] = idx;
            seed = (_a * seed + _c) % _m;
        }
        return selectedIdxList
    }

    function dispense(BuyerInfo[] memory buyerList) public {
        for (uint256 i = 0; i < buyerList.length; i++) {
            TicketGoNFT(nftToken).mint(
                buyerList[i].audienceAddress, buyerList[i].concertId, buyerList[i].credential, buyerList[i].areaName
            );
            emit EventDispense(buyerList[i].audienceAddress, buyerList[i]);
        }
    }

    function singleRefund(BuyerInfo memory buyerInfo) public payable {
        uint256 refundAmount = buyerInfo.amount;
        buyerInfo.amount = 0;
        (bool success,) = payable(buyerInfo.audienceAddress).call{value: refundAmount}("");
        emit EventRefund(buyerInfo.audienceAddress, success, buyerInfo);
    }

    function refund(BuyerInfo[] memory buyerList) public payable {
        for (uint256 i = 0; i < buyerList.length; i++) {
            singleRefund(buyerList[i]);
        }
    }

    // Final amount settlement
    function withdraw(uint256 _concertId) public payable onlyOwner {
        Concert memory concertInfo = concertOf(_concertId);
        address singerAddress = concertInfo.concertOwner;
        uint256 totalBalance = concertInfo.totalBalance;
        concertInfo.totalBalance = 0;
        uint256 singerAmount = (totalBalance * 90) / 100;
        uint256 operatorAmount = (totalBalance * 10) / 100;

        (bool singerSuccess,) = payable(singerAddress).call{value: singerAmount}("");
        (bool operatorSuccess,) = payable(_operator).call{value: operatorAmount}("");

        emit EventWithdraw(
            _concertId, singerSuccess, singerAddress, singerAmount, operatorSuccess, _operator, operatorAmount
        );
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