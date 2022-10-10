//SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import './LendingPool.sol';
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract LlamaLendFactory is Ownable {
    using Clones for address;

    LendingPool public immutable implementation;

    event PoolCreated(address indexed nftContract, address indexed owner, address pool);

    constructor(LendingPool implementation_) {
        implementation = implementation_;
    }

    function createPool(
        address _oracle, uint _maxPrice, address _nftContract, 
        uint _maxDailyBorrows, string memory _name, string memory _symbol,
        uint96 _maxLoanLength, LendingPool.Interests calldata interests
    ) external returns (LendingPool pool) {
        require(_maxLoanLength < 1e18, "maxLoanLength too big"); // 31bn years, makes sure that reverts cant be forced through this
        pool = LendingPool(address(implementation).clone());
        pool.initialize(_oracle, _maxPrice, _maxDailyBorrows, _name, _symbol, interests, msg.sender, _nftContract, address(this), _maxLoanLength);
        emit PoolCreated(_nftContract, msg.sender, address(pool));
    }

    function emergencyShutdown(address[] calldata pools) external onlyOwner {
        for(uint i = 0; i < pools.length; i++){
            LendingPool(pools[i]).emergencyShutdown();
        }
    }
}