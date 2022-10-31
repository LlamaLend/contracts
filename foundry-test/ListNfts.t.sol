// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../contracts/ListNfts.sol";
import "../contracts/mocks/MockNFT.sol";
import "../contracts/mocks/MockEnumerableNFT.sol";

contract ListNftsTest is Test {
    address owner = vm.addr(0x01);
    address somebody = vm.addr(0x02);
    address nobody = vm.addr(0x03);

    ListNfts listNfts;
    MockNFT mockNft;
    MockEnumerableNFT mockEnumerableNft;

    function setUp() public {
        listNfts = new ListNfts();
        mockNft = new MockNFT();
        mockEnumerableNft = new MockEnumerableNFT();

        mockNft.mint(2, owner);
        mockNft.mint(3, somebody);
        mockNft.mint(100, owner);

        mockEnumerableNft.mint(2, owner);
        mockEnumerableNft.mint(3, somebody);
        mockEnumerableNft.mint(100, owner);
    }

    function test_GetOwnedNftsFullRangeWithErc721() public {
        uint256[] memory nfts = listNfts.getOwnedNfts(owner, mockNft, 0, 5000);
        uint256 balance = mockNft.balanceOf(owner);
        assertEq(balance, 102);
        assertEq(nfts.length, balance);
    }

    function test_GetOwnedNftsPartialRangeWithErc721() public {
        uint256[] memory nfts = listNfts.getOwnedNfts(owner, mockNft, 1, 101);
        // in the range 0-99 inclusive three were minted to a different user
        assertEq(nfts.length, 97);

        nfts = listNfts.getOwnedNfts(owner, mockNft, 101, 201);
        // the remaining 4 will show up here.
        assertEq(nfts.length, 4);
    }

    function test_GetOwnedNftsNoResultsWithErc721() public {
        uint256[] memory nfts = listNfts.getOwnedNfts(nobody, mockNft, 1, 101);
        assertEq(nfts.length, 0);
    }

    function test_GetOwnedNftsFullRangeWithErc721Enumerable() public {
        uint256[] memory nfts = listNfts.getOwnedNfts(
            owner,
            mockEnumerableNft,
            1,
            5000
        );
        uint256 balance = mockEnumerableNft.balanceOf(owner);
        assertEq(nfts.length, balance);
    }

    function test_GetOwnedNftsPartialRangeWithErc721Enumerable() public {
        uint256[] memory nfts = listNfts.getOwnedNfts(
            owner,
            mockEnumerableNft,
            1,
            101
        );
        // in the range 1-100 inclusive three were minted to a different user
        assertEq(nfts.length, 97);

        nfts = listNfts.getOwnedNfts(owner, mockEnumerableNft, 101, 201);
        // the remaining 5 will show up here.
        assertEq(nfts.length, 5);
    }

    function test_GetOwnedNftsNoResultsWithErc721Enumerable() public {
        uint256[] memory nfts = listNfts.getOwnedNfts(
            nobody,
            mockEnumerableNft,
            1,
            101
        );
        assertEq(nfts.length, 0);
    }
}
