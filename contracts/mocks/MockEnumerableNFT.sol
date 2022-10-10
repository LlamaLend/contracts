//SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract MockEnumerableNFT is ERC721Enumerable {
    uint256 private _currentTokenId;

    constructor() ERC721("Mock Enumerable NFT", "MOCK") {}

    function mint(uint256 amount, address to) external {
        for (uint256 i = 0; i < amount; i++) {
            _mint(to, ++_currentTokenId);
        }
    }
}
