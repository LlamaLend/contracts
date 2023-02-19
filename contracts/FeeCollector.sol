//SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract FeeCollector is Ownable {
    using Address for address payable;

    function collect(uint amount, address payable to) external onlyOwner {
        to.sendValue(amount);
    }

    receive() external payable {}
}