//SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import './LendingPool.sol';
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract LlamaLendFactory is Ownable {
    using Clones for address;

    mapping(address => address[]) public nftPools;
    address[] public allPools;
    LendingPool public immutable implementation;

    event PoolCreated(address indexed nftContract, address indexed owner, address pool, uint);

    constructor(LendingPool implementation_) {
        implementation = implementation_;
    }

    function allPoolsLength() external view returns (uint) {
        return allPools.length;
    }

    function nftPoolsLength(address nftContract) external view returns (uint) {
        return nftPools[nftContract].length;
    }

    function createPool(
        address _oracle, uint _maxPrice, address _nftContract, 
        uint _maxDailyBorrows, string memory _name, string memory _symbol,
        uint _maxLoanLength, LendingPool.Interests calldata interests
    ) external returns (LendingPool pool) {
        require(_maxLoanLength < 1e18, "maxLoanLength too big"); // 31bn years, makes sure that reverts cant be forced through this
        pool = LendingPool(address(implementation).clone());
        pool.initialize(_oracle, _maxPrice, _maxDailyBorrows, _name, _symbol, interests, msg.sender, _nftContract, address(this), _maxLoanLength);
        allPools.push(address(pool));
        nftPools[_nftContract].push(address(pool));
        emit PoolCreated(_nftContract, msg.sender, address(pool), allPools.length);
    }

    function emergencyShutdown(uint[] calldata pools) external onlyOwner {
        for(uint i = 0; i < pools.length; i++){
            LendingPool(allPools[pools[i]]).emergencyShutdown();
        }
    }
}