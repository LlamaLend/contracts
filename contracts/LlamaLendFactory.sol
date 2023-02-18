//SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import './LendingPool.sol';
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract LlamaLendFactory is Ownable {
    using Clones for address;
    using Address for address payable;

    LendingPool public immutable implementation;
    string public baseUri =  "https://nft.llamalend.com/nft2/";

    event PoolCreated(address pool, address owner);

    constructor(LendingPool implementation_) {
        implementation = implementation_;
    }

    struct NewPool {
        uint maxPrice;
        uint maxLoanLength;
        address nftContract;
        uint96 maxVariableInterestPerEthPerSecond;
        uint96 minimumInterest;
        uint ltv;
    }
    function createPool(
        address _oracle, 
        uint _maxDailyBorrows, string memory _name, string memory _symbol, NewPool[] calldata pools
    ) external payable returns (LendingPool pool) {
        pool = LendingPool(address(implementation).clone());
        pool.initialize(_oracle, _maxDailyBorrows, _name, _symbol, address(this));
        for(uint i = 0; i<pools.length; i++){
            NewPool calldata poolParams = pools[i];
            require(poolParams.maxLoanLength < 1e18, "maxLoanLength too big"); // 31bn years, makes sure that reverts cant be forced through this
            pool.enablePool(poolParams.nftContract, poolParams.maxVariableInterestPerEthPerSecond, poolParams.minimumInterest, 
                poolParams.ltv, poolParams.maxPrice, poolParams.maxLoanLength);
        }
        pool.transferOwnership(msg.sender);
        pool.deposit{value: msg.value}();
        emit PoolCreated(address(pool), msg.sender);
    }

    struct PoolToShutdown {
        address pool;
        bytes32 poolHash;
    }
    function emergencyShutdown(PoolToShutdown[] calldata pools) external onlyOwner {
        for(uint i = 0; i < pools.length; i++){
            PoolToShutdown calldata pool = pools[i];
            LendingPool(pool.pool).emergencyShutdown(pool.poolHash);
        }
    }

    function setBaseUri(string memory _baseUri) external onlyOwner {
        baseUri = _baseUri;
    }

    struct LoanRepayment {
        address pool;
        LendingPool.Loan[] loans;
    }
    function repay(LoanRepayment[] calldata loansToRepay) external payable {
        uint length = loansToRepay.length;
        uint i = 0;
        while(i<length){
            LendingPool(loansToRepay[i].pool).repay{value: address(this).balance}(loansToRepay[i].loans, msg.sender);
            unchecked {
                i++;
            }
        }
        payable(msg.sender).sendValue(address(this).balance);
    }

    receive() external payable {}
}