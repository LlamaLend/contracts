//SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

// Only meant as a crutch for frontend, this contract will only be used off-chain
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
        // uint256 length = 0;

        // we only need to check this stuff if there is a balance
        if (balance > 0) {
            uint256 length = 0;
            // check to see if it is enumerable
            if (
                nftContract.supportsInterface(
                    type(IERC721Enumerable).interfaceId
                )
            ) {
                // NOTE: this assumes it actually implements the functions, no error handling
                IERC721Enumerable enumerable = IERC721Enumerable(
                    address(nftContract)
                );
                while (balance != 0) {
                    unchecked {
                        // unchecked: always greater than 0 here
                        --balance;
                    }
                    uint256 tokenId = enumerable.tokenOfOwnerByIndex(
                        owner,
                        balance
                    );
                    if (tokenId >= start && tokenId < end) {
                        nfts[length] = tokenId;
                        unchecked {
                            // unchecked: always less than end minus start
                            length++;
                        }
                    }
                }
            } else {
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
            }
            // resize the array to the found number of tokens
            if (length != nfts.length) {
                assembly {
                    mstore(nfts, length)
                }
            }
        }
    }
}
