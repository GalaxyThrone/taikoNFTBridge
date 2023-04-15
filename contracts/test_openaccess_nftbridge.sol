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

contract openAccessNFTBridge is Ownable, IERC721Receiver {
    using Counters for Counters.Counter;

    ITaikoBridgeContract taikoBridge;

    //@notice we use two different starting points for either chain to prevent overlap.
    Counters.Counter private _tokenIdCounter;

    //@notice hardcoded for accessibility

    address public taikoBridgeContract =
        0xbB203a6f73F805E44E97dcC0c894eFe0fAf72498; // SignalService Taiko

    address public sepoliaBridgeContract =
        address(0x07130410064Ab5C32486CC36904fb219ae97156F); // SignalService Sepolia

    uint public sepoliaChainId = 11155111; //ChainID Sepolia

    uint public taikoChainId = 167004; //ChainID Taiko A2

    uint public currentChainType = 0; // 1 for L1, 2 for L2

    address public currentBridgeSignalContract;

    //the bridgeContract on the other side of the aisle
    address public currentSisterContract;

    uint public currentChainId;

    uint public currentSisterChainId;

  
    //@TODO (bad notes, deprecated. Wrote down the new approach)

    //@notice

    //@the NFT Contract itself has to send it here. (so the User has to Approve it first.)  It does need to implement the new interface (to be coded), specifically the data field.

    //@notice the sister contract should implement a custom logic to enable a remint of the bridged over nft via the bool isSignalReceived. If its true, mint the bridged over asset.

    //so onERC721 received, we get the encoded bytes data to forward, to who we have to send it, for what tokenId, and an optional bytes32 datafield.

    //so L2 NFT Contract has to do:

    //Get approved to send the NFT
    //Send NFT + argument: bytes calldata data

    // the argument bytes calldata data has to have:

    //  uint: tokenId, address: origin(to prove their NFT Contract sent it), tokenURI?(no, the L1 Sister Contract has to know it on its own.)
    //* perhaps optional address: NFTSisterContractOtherChain stored somewhere by the NFT Contract creator

    // we transfer the data via the signalService, and encode the bytes argument to a bytes32 (padding?)

    // on the other chain, the L1SisterNFT Contract needs to implement an interface:

    // ping OUR bridge contract to ask if a specific tokenId, for a specific origin Address, has sucessfully bridged over
    // OUR Bridge Contract flips a switch if the bool is returned as true to mark this bridgedNFT as claimed

    // the SisterNFT Contract then has to implement their bridgedMint somehow with the tokenId from the other Chain and make a normal NFT Mint

    // done.






    //ownerWhoSentTheNFT => NFT Contract => tokenId => Boolean (true if its being held)
    mapping(address => mapping(address => mapping(uint => bool))) heldNFT;


    mapping(address => address ) public sisterContract;

    function addSisterContract(address _newSisterContract) external {

        sisterContract[msg.sender] = _newSisterContract;
    }


    function claimBridged(bytes32 _dataPayload, bytes32 _signal) external returns(bool){


    }



    // NFTContract => User => TokenId => bytes32 storageSlot
    mapping(address => mapping(address => mapping(uint => bytes32))) public bridgeRequest;
       

    //@notice bridge over NFT to sister chain
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) public override returns (bytes4) {
        //@TODO delete afterwards to save gas, just makes it more readable.
        address nftContractAddr = msg.sender;

        uint256 tokenId = tokenId;


        //@TODO what should we use the data field for, tokenURI perhaps? Overkill possibly, or plain useless.
        bytes32 encodedData = encodeMessagePayload(
            nftContractAddr,
            from,
            tokenId
        );

        //@TODO we need to work with this in the backend!

        // getSignalSlot would also work, to save gas
        bridgeRequest[nftContractAddr][from][tokenId] = pingBridgeForTransfer(
            encodedData
        );

        //@todo can I ignore this?
        return this.onERC721Received.selector;
    }

    function pingBridgeForTransfer(
        bytes32 _dataPayload
    ) internal returns (bytes32) {
        taikoBridge = ITaikoBridgeContract(currentBridgeSignalContract);

        return taikoBridge.sendSignal(_dataPayload);
    }

    //@notice decode data payload to bytes32 for cross-chain messaging
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

    //@notice decode data payload from bytes32 for cross-chain messaging
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
