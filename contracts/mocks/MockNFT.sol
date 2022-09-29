//SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MockNFT is ERC721 {
    constructor() ERC721("Mock NFT", "MOCK"){}

    function mint(uint amount, address to) external {
        for(uint i = 0; i<amount; i++){
            _mint(to, i);
        }
    }
}