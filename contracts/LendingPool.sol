//SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./libs/upgradeable/ERC721Upgradeable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import {Clone} from "./libs/Clone.sol";

contract LendingPool is OwnableUpgradeable, ERC721Upgradeable, Clone {
    using Address for address payable;

    struct Loan {
        address nftContract;
        uint96 interest; // allows up to 2.49e+38% interest
        uint nft;
        uint40 startTime; // safe until year 231,800
        uint216 borrowed; // would need to borrow 1e+47 ETH -> that much ETH doesnt even exist
        uint deadline;
    }

    mapping(bytes32=>uint) public pools; // Will just be 1 or 0, a boolean implemented as a uint to save gas

    address public oracle;
    address public factory;
    uint public totalBorrowed; // = 0;
    string private constant baseURI = "https://nft.llamalend.com/nft2/";
    uint public maxDailyBorrows; // IMPORTANT: an attacker can borrow up to 150% of this limit if they prepare beforehand
    uint public reservedForWithdrawals;
    uint216 public currentDailyBorrows;
    uint40 public lastUpdateDailyBorrows;
    mapping(address => bool) public liquidators;

    event Borrowed(uint currentDailyBorrows, uint newBorrowedAmount);
    event ReducedDailyBorrows(uint currentDailyBorrows, uint amountReduced);
    event LoanCreated(uint indexed loanId, address nftContract, uint nft, uint interest, uint startTime, uint216 borrowed);
    event LiquidatorAdded(address liquidator);
    event LiquidatorRemoved(address liquidator);
    event PoolEnabled(bytes32 poolHash, address nftContract, uint96 maxVariableInterestPerEthPerSecond, uint96 minimumInterest, uint ltv, uint maxPrice, uint maxLoanLength);
    event PoolDisabled(bytes32 poolHash);

    function initialize(address _oracle, uint _maxDailyBorrows, string memory _name,
        string memory _symbol, address _factory) initializer public
    {
        __Ownable_init_unchained();
        __ERC721_init_unchained(_name, _symbol);
        require(_oracle != address(0), "oracle can't be 0");
        oracle = _oracle;
        maxDailyBorrows = _maxDailyBorrows;
        lastUpdateDailyBorrows = uint40(block.timestamp);
        factory = _factory;
    }

    function addDailyBorrows(uint216 toAdd) internal {
        uint elapsed = block.timestamp - uint256(lastUpdateDailyBorrows);
        uint toReduce = (maxDailyBorrows*elapsed)/(1 days);
        if(toReduce > currentDailyBorrows){
            currentDailyBorrows = toAdd;
        } else {
            currentDailyBorrows = uint216(currentDailyBorrows - toReduce) + toAdd;
        }
        require(currentDailyBorrows < maxDailyBorrows, "max daily borrow");
        lastUpdateDailyBorrows = uint40(block.timestamp);
        emit Borrowed(currentDailyBorrows, toAdd);
    }

    function getLoanId(
        address nftContract,
        uint96 interest,
        uint nftId,
        uint40 startTime,
        uint216 price,
        uint deadline
    ) public pure returns (uint id) {
        return uint(keccak256(abi.encode(nftContract, interest, nftId, startTime, price, deadline)));
    }

    function getPoolHash(address nftContract, uint96 maxVariableInterestPerEthPerSecond, uint96 minimumInterest, uint ltv, uint maxPrice, uint maxLoanLength) public pure returns (bytes32 id) {
        return keccak256(abi.encode(nftContract, maxVariableInterestPerEthPerSecond, minimumInterest, ltv, maxPrice, maxLoanLength));
    }

    function _borrow(
        address nftContract,
        uint nftId,
        uint216 price,
        uint96 interest,
        uint deadline) internal {
        uint id = getLoanId(nftContract, interest, nftId, uint40(block.timestamp), price, deadline);
        require(!_exists(id), "ERC721: token already minted");
        _owners[id] = msg.sender;
        emit LoanCreated(id, nftContract, nftId, interest, block.timestamp, price);
        emit Transfer(address(0), msg.sender, id);
        IERC721(nftContract).transferFrom(msg.sender, address(this), nftId);
    }

    function calculateInterest(uint priceOfNextItems, uint96 maxVariableInterestPerEthPerSecond, uint96 minimumInterest) internal view returns (uint96 interest) {
        uint borrowed = priceOfNextItems/2 + totalBorrowed;
        uint variableRate = (borrowed * uint256(maxVariableInterestPerEthPerSecond)) / (address(this).balance + totalBorrowed - reservedForWithdrawals);
        interest = minimumInterest + uint96(variableRate); // variableRate <= maxVariableInterestPerEthPerSecond <= type(uint96).max, so casting is safe
    }

    struct PoolData {
        address nftContract;
        uint96 maxVariableInterestPerEthPerSecond;
        uint96 minimumInterest;
        uint ltv;
        uint maxPrice;
        uint maxLoanLength;
    }

    struct Signature {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    function borrow(
        // Call params
        uint[] calldata nftId,
        uint216 price,
        uint256 deadline,
        // Slippage checks
        uint256 maxInterest,
        uint256 totalToBorrow,
        // Pool data
        PoolData calldata poolData, // To get around Stack too deep
        // Signature
        Signature calldata signature // To get around Stack too deep
    ) external {
        checkOracle(poolData.nftContract, price, deadline, poolData.maxPrice, signature.v, signature.r, signature.s); // Also checks that loans for `nftContract` are accepted in this pool by reverting if maxPrice == 0
        bytes32 poolHash = getPoolHash(poolData.nftContract, poolData.maxVariableInterestPerEthPerSecond, poolData.minimumInterest, poolData.ltv, poolData.maxPrice, poolData.maxLoanLength);
        require(pools[poolHash] == 1, "Nonexisting pool");
        // LTV can be manipulated by pool owner to change price in any way, however we check against user provided value so it shouldnt matter
        // Conversion to uint216 doesnt really matter either because it will only change price if LTV is extremely high
        // and pool owner can achieve the same anyways by setting a very low LTV
        price = uint216((uint256(price) * poolData.ltv) / 1e18);
        uint length = nftId.length;
        uint borrowedNow = price * length;
        require(borrowedNow == totalToBorrow, "ltv changed");
        require(borrowedNow <= (address(this).balance - reservedForWithdrawals));
        uint96 interest = calculateInterest(borrowedNow, poolData.maxVariableInterestPerEthPerSecond, poolData.minimumInterest);
        require(interest <= maxInterest);
        totalBorrowed += borrowedNow;
        uint loanDeadline = block.timestamp + poolData.maxLoanLength;
        uint i = 0;
        while(i<length){
            _borrow(poolData.nftContract, nftId[i], price, interest, loanDeadline);
            unchecked {
                i++;
            }
        }
        _balances[msg.sender] += length;
        // it's okay to restrict borrowedNow to uint216 because we will send that amount in ETH, and that much ETH doesnt exist
        addDailyBorrows(uint216(borrowedNow));
        payable(msg.sender).sendValue(borrowedNow);
    }

    function _burnWithoutBalanceChanges(uint tokenId, address owner) internal {
        // Clear approvals
        _approve(address(0), tokenId);

        delete _owners[tokenId];

        emit Transfer(owner, address(0), tokenId);
    }

    function _repay(Loan calldata loan, address from) internal returns (uint) {
        uint loanId = getLoanId(loan.nftContract, loan.interest, loan.nft, loan.startTime, loan.borrowed, loan.deadline);
        require(ownerOf(loanId) == from, "not owner");
        uint borrowed = loan.borrowed;
        uint sinceLoanStart = block.timestamp - loan.startTime;
        // No danger of overflow, if it overflows it means that user would need to pay 1e41 eth, which is impossible to pay anyway
        uint interest = (sinceLoanStart * uint256(loan.interest) * borrowed) / 1e18;
        if(block.timestamp > loan.deadline){
            interest += ((block.timestamp - uint256(loan.deadline))*borrowed)/(1 days);
        }
        totalBorrowed -= borrowed;
        _burnWithoutBalanceChanges(loanId, from);

        if(sinceLoanStart < (1 days)){
            uint until24h;
            unchecked {
                until24h = (1 days) - sinceLoanStart;
            }
            uint toReduce = (borrowed*until24h)/(1 days);
            if(toReduce < currentDailyBorrows){
                unchecked {
                    // toReduce < currentDailyBorrows always so it's fine to restrict to uint216 because currentDailyBorrows is uint216 already
                    currentDailyBorrows = currentDailyBorrows - uint216(toReduce);
                }
                emit ReducedDailyBorrows(currentDailyBorrows, toReduce);
            } else {
                emit ReducedDailyBorrows(0, currentDailyBorrows);
                currentDailyBorrows = 0;
            }
        }

        IERC721(loan.nftContract).transferFrom(address(this), from, loan.nft);
        return interest + borrowed;
    }

    function repay(Loan[] calldata loansToRepay, address from) external payable {
        require(msg.sender == from || msg.sender == factory); // Factory enforces that from is msg.sender
        uint length = loansToRepay.length;
        uint totalToRepay = 0;
        uint i = 0;
        while(i<length){
            totalToRepay += _repay(loansToRepay[i], from);
            unchecked {
                i++;
            }
        }
        _balances[from] -= length;
        payable(msg.sender).sendValue(msg.value - totalToRepay); // overflow checks implictly check that amount is enough
    }

    // Liquidate expired loan
    function doEffectiveAltruism(Loan calldata loan, address to) external {
        require(liquidators[msg.sender] == true);
        uint loanId = getLoanId(loan.nftContract, loan.interest, loan.nft, loan.startTime, loan.borrowed, loan.deadline);
        require(_exists(loanId), "loan closed");
        require(block.timestamp > loan.deadline, "not expired");
        totalBorrowed -= loan.borrowed;
        _burn(loanId);
        IERC721(loan.nftContract).transferFrom(address(this), to, loan.nft);
    }

    function setOracle(address newValue) external onlyOwner {
        require(newValue != address(0), "oracle can't be 0");
        oracle = newValue;
    }

    function setMaxDailyBorrows(uint _maxDailyBorrows) external onlyOwner {
        maxDailyBorrows = _maxDailyBorrows;
    }

    function setReservedForWithdrawals(uint _reservedForWithdrawals) external onlyOwner {
        reservedForWithdrawals = _reservedForWithdrawals;
    }

    function deposit() external payable {}

    function withdraw(uint amount) external onlyOwner {
        payable(msg.sender).sendValue(amount);
        if(amount < reservedForWithdrawals){
            unchecked{
                reservedForWithdrawals -= amount;
            }
        } else if (reservedForWithdrawals != 0{
            reservedForWithdrawals = 0;
        }
    }

    function checkOracle(
        address nftContract,
        uint216 price,
        uint256 deadline,
        uint maxPrice,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public view {
        require(block.timestamp < deadline, "deadline over");
        require(
            ecrecover(
                keccak256(
                    abi.encodePacked(
                        "\x19Ethereum Signed Message:\n111",
                        price,
                        deadline,
                        block.chainid,
                        nftContract
                    )
                ),
                v,
                r,
                s
            ) == oracle,
            "not oracle"
        );
        require(price < maxPrice, "max price");
    }

    function infoToRepayLoan(Loan calldata loan) view external returns (uint totalRepay, uint principal, uint interest, uint lateFees){
        interest = ((block.timestamp - loan.startTime) * loan.interest * loan.borrowed) / 1e18;
        if(block.timestamp > loan.deadline){
            lateFees = ((block.timestamp - loan.deadline)*loan.borrowed)/(1 days);
        } else {
            lateFees = 0;
        }
        principal = loan.borrowed;
        totalRepay = principal + interest + lateFees;
    }

    function currentAnnualInterest(uint priceOfNextItem, uint96 maxVariableInterestPerEthPerSecond, uint96 minimumInterest) external view returns (uint interest) {
        uint96 interestPerSecond;
        if(address(this).balance + totalBorrowed == 0){
            interestPerSecond = minimumInterest;
        } else {
            interestPerSecond = calculateInterest(priceOfNextItem, maxVariableInterestPerEthPerSecond, minimumInterest);
        }
        return interestPerSecond * 365 days;
    }

    function getDailyBorrows() external view returns (uint maxInstantBorrow, uint dailyBorrows, uint maxDailyBorrowsLimit) {
        uint elapsed = block.timestamp - lastUpdateDailyBorrows;
        dailyBorrows = currentDailyBorrows - Math.min((maxDailyBorrows*elapsed)/(1 days), currentDailyBorrows);
        maxDailyBorrowsLimit = maxDailyBorrows;
        maxInstantBorrow = Math.min(address(this).balance, maxDailyBorrows - dailyBorrows);
    }

    function _baseURI() internal view override returns (string memory) {
        return string(abi.encodePacked(baseURI, Strings.toString(block.chainid), "/", Strings.toHexString(uint160(address(this)), 20), "/"));
    }

    function enablePool(
        address nftContract,
        uint96 maxVariableInterestPerEthPerSecond, // eg: 80% p.a. = 25367833587 ~ 0.8e18 / 1 years;
        uint96 minimumInterest, // eg: 40% p.a. = 12683916793 ~ 0.4e18 / 1 years;
        uint ltv, // out of 1e18, eg: 33% = 0.33e18
        uint maxPrice,
        uint maxLoanLength
    ) external onlyOwner {
        bytes32 poolHash = getPoolHash(nftContract, maxVariableInterestPerEthPerSecond, minimumInterest, ltv, maxPrice, maxLoanLength);
        pools[poolHash] = 1;
        emit PoolEnabled(poolHash, nftContract, maxVariableInterestPerEthPerSecond, minimumInterest, ltv, maxPrice, maxLoanLength);
    }

    function disablePool(bytes32 poolHash) external onlyOwner {
        pools[poolHash] = 0;
        emit PoolDisabled(poolHash);
    }

    function addLiquidator(address liq) external onlyOwner {
        liquidators[liq] = true;
        emit LiquidatorAdded(liq);
    }

    function removeLiquidator(address liq) external onlyOwner {
        liquidators[liq] = false;
        emit LiquidatorRemoved(liq);
    }

    function emergencyShutdown(bytes32 poolHash) external {
        require(msg.sender == factory);
        pools[poolHash] = 0; // prevents new borrows
    }
}
