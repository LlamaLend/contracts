pragma solidity ^0.8.0;

import './LendingPool.sol';
import "@openzeppelin/contracts/access/Ownable.sol";

contract LlamaLendFactory is Ownable {
    mapping(address => address[]) public nftPools;
    address[] public allPools;

    event PoolCreated(address indexed nftContract, address indexed owner, address pool, uint);

    function allPoolsLength() external view returns (uint) {
        return allPools.length;
    }

    function nftPoolsLength(address nftContract) external view returns (uint) {
        return nftPools[nftContract].length;
    }

    function createPool(
        address _oracle, uint _maxPrice, address _nftContract, 
        uint _maxDailyBorrows, string memory _name, string memory _symbol,
        uint _maxLoanLength, uint _maxInterestPerEthPerSecond
    ) external returns (address pool) {
        pool = address(new LendingPool(_oracle, _maxPrice, _nftContract, _maxDailyBorrows, _name, _symbol, _maxLoanLength, _maxInterestPerEthPerSecond, msg.sender));
        allPools.push(pool);
        nftPools[_nftContract].push(pool);
        emit PoolCreated(_nftContract, msg.sender, pool, allPools.length);
    }

    function emergencyShutdown(uint[] calldata pools) external onlyOwner {
        for(uint i = 0; i < pools.length; i++){
            LendingPool(allPools[pools[i]]).emergencyShutdown();
        }
    }
}