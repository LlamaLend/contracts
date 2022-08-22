//SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract ListNfts {
    function getOwnedNfts(address owner, IERC721 nftContract, uint start, uint end) external view returns (uint[100] memory nfts, uint length){
        length = 0;
        while(start < end){
            try nftContract.ownerOf(start) returns (address nftOwner) { 
                if(nftOwner == owner){
                    nfts[length] = start;
                    unchecked {
                        length++;
                    }
                }
            } catch {}
            unchecked {
                start++;
            }
        }
    }
}