// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

interface ITaikoBridgeContract {
    function sendSignal(bytes32 signal) external returns (bytes32 storageSlot);

    function getSignalSlot(
        address app,
        bytes32 signal
    ) external returns (bytes32);

    function isSignalReceived(
        uint256 srcChainId,
        address app,
        bytes32 signal,
        bytes calldata proof
    ) external returns (bool);
}

// Abstract contract, add appropriate functionality later
abstract contract WrappedNFT {
    function claimBridged(uint256 srcChainId,
        address app,
        bytes32 signal,
        bytes calldata proof
    ) public virtual returns (bool,address,address,uint);

    function addSisterContract(address _newSisterContractOnOtherChain) public virtual;
}

// Contract for open access NFT bridge
contract openAccessNFTBridge is Ownable, IERC721Receiver {
    using Counters for Counters.Counter;

    ITaikoBridgeContract taikoBridge;

    // Use different starting points for each chain to prevent overlap
    Counters.Counter private _tokenIdCounter;

    // Define bridge and chain contracts and IDs
    address public taikoBridgeContract =
        	address(0x0000777700000000000000000000000000000007); // SignalService Taiko

    address public sepoliaBridgeContract =
        address(0x11013a48Ad87a528D23CdA25D2C34D7dbDA6b46b); // SignalService Sepolia

    uint public sepoliaChainId = 11155111; //ChainID Sepolia

    uint public taikoChainId = 167002; //ChainID Taiko A2

    uint public currentChainType = 0; // 1 for L1, 2 for L2

    address public currentBridgeSignalContract;

    // The bridge contract on the other side
    address public currentSisterContract;

    bool sisterBridgeSetup =false;

    uint public currentChainId;

    uint public currentSisterChainId;


    event bridgeRequestSent(
        address owner,
        address indexednftContract,
        uint indexed nftId
    );

    // Constructor function for the contract
    constructor(
        uint _chainType
    ) {
        currentChainType = _chainType;
        
        if (_chainType == 1) {
            currentBridgeSignalContract = sepoliaBridgeContract;

            currentChainId = sepoliaChainId;
            currentSisterChainId = taikoChainId;
        }

        if (_chainType == 2) {
            currentBridgeSignalContract = sepoliaBridgeContract;

            currentChainId = taikoChainId;
            currentSisterChainId = sepoliaChainId;
        }
    }

    // Mapping to store NFTs being held
    mapping(address => mapping(address => mapping(uint => bool))) heldNFT;

    mapping(address => address) public sisterContract;


    // Add a new sister contract
    function addSisterContract(address _newSisterContract) external {
        sisterContract[msg.sender] = _newSisterContract;
    }

    // Add a sister contract via signature
    function addSisterContractViaSignature(address _newSisterContract, bytes memory _signature) external {
        // TODO

        // for non-upgradable NFT Contracts to be L2 Bridge compliant
    }

    function addSisterBridgeContract(address _SisterContractInit) external onlyOwner{

        //sister bridge contract can only be set up once
        require(!sisterBridgeSetup, "A contract is a contract is a contract!");
        sisterBridgeSetup = true;
        currentSisterContract  = _SisterContractInit;

    }

    // Returns true or false if message received, the original NFT Contract address from the other chain, the owner of the NFT, and the tokenId
    function claimBridged(
        uint256 srcChainId,
        address _origin,
        bytes32 _dataPayload,
        bytes calldata proof
    ) external returns (bool,address,address,uint) {
        taikoBridge = ITaikoBridgeContract(currentBridgeSignalContract);


        require(_origin == currentSisterContract, "I have never seen this Man/BridgeContract in my life!");
        bool response = taikoBridge.isSignalReceived(
            srcChainId,
            _origin,
            _dataPayload,
            proof
        );

        (
            address _addrOwner,
            address _addrOriginNftContract,
            uint256 _nftId
        ) = decodeMessagePayload(_dataPayload);

        // If we hold the NFT from a previous bridging, we return it to the owner here.
        if (
            heldNFT[_addrOwner][sisterContract[_addrOriginNftContract]][_nftId]
        ) {
            address sisterContractAddress = sisterContract[_addrOriginNftContract];

            require(sisterContractAddress != address(0), "no sister contract specified!");

            IERC721 sisterNftContract = IERC721(sisterContractAddress);

            sisterNftContract.safeTransferFrom(
                sisterContractAddress,
                _addrOwner,
                _nftId
            );

            return (response, address(0),address(0),0);
        }

        return (response, _addrOriginNftContract,_addrOwner,_nftId);
    }


       


    //requestId => storageSlot;
    mapping(uint => bytes32) storageSlotsBridgeRequest;

    mapping(uint => uint) blockNumber;
    mapping(uint => address) bridgeRequestInitiatorUser;


    mapping(uint => address) bridgeRequestInitiatorSender;
    uint totalRequestsSent;



    

    // Bridge NFT to sister chain
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) public override returns (bytes4) {
        address nftContractAddr = msg.sender;

        bytes32 encodedData = encodeMessagePayload(
            nftContractAddr,
            from,
            tokenId
        );

     
        
        storageSlotsBridgeRequest[totalRequestsSent] = pingBridgeForTransfer(
            encodedData
        );
        bridgeRequestInitiatorUser[totalRequestsSent] = from ;
        bridgeRequestInitiatorSender[totalRequestsSent] = msg.sender;
        blockNumber[totalRequestsSent] = block.number;
        totalRequestsSent++;
        heldNFT[from][nftContractAddr][tokenId] = true;
       

        emit bridgeRequestSent(from, msg.sender, tokenId);

    
        return this.onERC721Received.selector;
    }

    function pingBridgeForTransfer(
        bytes32 _dataPayload
    ) internal returns (bytes32) {
        taikoBridge = ITaikoBridgeContract(currentBridgeSignalContract);

        return taikoBridge.sendSignal(_dataPayload);
    }

    // Encode data payload to bytes32 for cross-chain messaging
    function encodeMessagePayload(
        address _addrOwner,
        address _addrOriginNftContract,
        uint256 _nftId
    ) public pure returns (bytes32) {
        bytes32 encoded = keccak256(
            abi.encode(_addrOwner, _addrOriginNftContract, _nftId)
        );

        return (encoded);
    }

    // Decode data payload from bytes32 for cross-chain messaging
    function decodeMessagePayload(
        bytes32 encodedMessageNFTBridge
    ) public pure returns (address, address, uint256) {
        (
            address _addrOwner,
            address _addrOriginNftContract,
            uint256 _nftId
        ) = abi.decode(
                abi.encodePacked(encodedMessageNFTBridge),
                (address, address, uint256)
            );
        return (_addrOwner, _addrOriginNftContract, _nftId);
    }
}
