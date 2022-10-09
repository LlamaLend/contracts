//SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract ListNfts {
    function getOwnedNfts(
        address owner,
        IERC721 nftContract,
        uint256 start,
        uint256 end
    ) external view returns (uint256[] memory nfts) {
        // make sure the array can hold all the possible tokens
        uint256 balance = nftContract.balanceOf(owner);
        // we can't have more than the balance
        nfts = new uint256[](balance);
        uint256 length = 0;
        while (start < end) {
            try nftContract.ownerOf(start) returns (address nftOwner) {
                if (nftOwner == owner) {
                    nfts[length] = start;
                    unchecked {
                        // unchecked: always less than end minus start
                        length++;
                    }
                }
            } catch {}
            unchecked {
                // unchecked: start is always less than end
                start++;
            }
        }
        // resize the array to the found number of token ids
        if (length != nfts.length) {
            assembly {
                mstore(nfts, length)
            }
        }
    }
}
