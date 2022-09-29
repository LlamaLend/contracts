//SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import "../libs/ERC721A.sol";

contract MockNFT is ERC721A {
    constructor() ERC721A("Mock NFT", "MOCK"){}

    function mint(uint amount, address to) external {
        _mint(to, amount);
    }
}