//SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./libs/ERC721.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract LendingPool is Ownable, ERC721 {
    using Address for address payable;

    struct Loan {
        uint nft;
        uint interest;
        uint40 startTime; // safe until year 231,800
        uint216 borrowed; // would need to borrow 1e+47 ETH -> that much ETH doesnt even exist
    }

    IERC721 public immutable nftContract;
    uint256 public immutable maxLoanLength;
    uint256 public maxVariableInterestPerEthPerSecond; // eg: 80% p.a. = 25367833587 ~ 0.8e18 / 1 years;
    uint256 public minimumInterest; // eg: 40% p.a. = 12683916793 ~ 0.4e18 / 1 years;
    uint256 public ltv; // out of 1e18, eg: 33% = 0.33e18
    address public immutable factory;
    uint256 public maxPrice;
    address public oracle;
    uint public totalBorrowed; // = 0;
    string private constant baseURI = "https://nft.llamalend.com/nft/";
    uint maxDailyBorrows; // IMPORTANT: an attacker can borrow up to 150% of this limit if they prepare beforehand
    uint216 currentDailyBorrows;
    uint40 lastUpdateDailyBorrows;
    mapping(address => bool) public liquidators;

    event Borrowed(uint currentDailyBorrows, uint newBorrowedAmount);
    event ReducedDailyBorrows(uint currentDailyBorrows, uint amountReduced);
    event LoanCreated(uint indexed loanId, uint nft, uint interest, uint startTime, uint216 borrowed);
    event LiquidatorAdded(address liquidator);
    event LiquidatorRemoved(address liquidator);

    constructor(address _oracle, uint _maxPrice, address _nftContract,
        uint _maxDailyBorrows, string memory _name, string memory _symbol,
        uint _maxLoanLength, uint _maxVariableInterestPerEthPerSecond, uint _minimumInterest, uint _ltv, address _owner) ERC721(_name, _symbol)
    {
        require(_oracle != address(0), "oracle can't be 0");
        require(_maxLoanLength < 1e18, "maxLoanLength too big"); // 31bn years, makes sure that reverts cant be forced through this
        oracle = _oracle;
        maxPrice = _maxPrice;
        nftContract = IERC721(_nftContract);
        maxDailyBorrows = _maxDailyBorrows;
        lastUpdateDailyBorrows = uint40(block.timestamp);
        maxLoanLength = _maxLoanLength;
        maxVariableInterestPerEthPerSecond = _maxVariableInterestPerEthPerSecond;
        minimumInterest = _minimumInterest;
        ltv = _ltv;
        transferOwnership(_owner);
        factory = msg.sender;
    }

    function addDailyBorrows(uint216 toAdd) internal {
        uint elapsed = block.timestamp - lastUpdateDailyBorrows;
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
        uint nftId,
        uint interest,
        uint startTime,
        uint216 price
    ) public pure returns (uint id) {
        return uint(keccak256(abi.encode(nftId, interest, startTime, price)));
    }

    function _borrow(
        uint nftId,
        uint216 price,
        uint interest) internal {
        uint id = getLoanId(nftId, interest, block.timestamp, price);
        require(!_exists(id), "ERC721: token already minted");
        _owners[id] = msg.sender;
        emit LoanCreated(id, nftId, interest, block.timestamp, price);
        emit Transfer(address(0), msg.sender, id);
        nftContract.transferFrom(msg.sender, address(this), nftId);
    }

    function calculateInterest(uint priceOfNextItems) internal view returns (uint interest) {
        uint borrowed = priceOfNextItems/2 + totalBorrowed;
        uint variableRate = (borrowed * maxVariableInterestPerEthPerSecond) / (address(this).balance + totalBorrowed);
        return minimumInterest + variableRate;
    }

    function borrow(
        uint[] calldata nftId,
        uint216 price,
        uint256 deadline,
        uint256 maxInterest,
        uint256 totalToBorrow,
        uint8 v,
        bytes32 r,
        bytes32 s) external {
        checkOracle(price, deadline, v, r, s);
        // LTV can be manipulated by pool owner to change price in any way, however we check against user provided value so it shouldnt matter
        // Conversion to uint216 doesnt really matter either because it will only change price if LTV is extremely high
        // and pool owner can achieve the same anyways by setting a very low LTV
        price = uint216((price * ltv) / 1e18);
        uint length = nftId.length;
        uint borrowedNow = price * length;
        require(borrowedNow == totalToBorrow, "ltv changed");
        uint interest = calculateInterest(borrowedNow);
        require(interest <= maxInterest);
        totalBorrowed += borrowedNow;
        uint i = 0;
        while(i<length){
            _borrow(nftId[i], price, interest);
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

    function _repay(Loan calldata loan) internal returns (uint) {
        uint loanId = getLoanId(loan.nft, loan.interest, loan.startTime, loan.borrowed);
        require(ownerOf(loanId) == msg.sender, "not owner");
        uint borrowed = loan.borrowed;
        uint sinceLoanStart = block.timestamp - loan.startTime;
        // No danger of overflow, if it overflows it means that user would need to pay 1e41 eth, which is impossible to pay anyway
        uint interest = (sinceLoanStart * loan.interest * borrowed) / 1e18;
        if(sinceLoanStart > maxLoanLength){
            interest += ((sinceLoanStart - maxLoanLength)*borrowed)/(1 days);
        }
        totalBorrowed -= borrowed;
        _burnWithoutBalanceChanges(loanId, msg.sender);

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

        nftContract.transferFrom(address(this), msg.sender, loan.nft);
        return interest + borrowed;
    }

    function repay(Loan[] calldata loansToRepay) external payable {
        uint length = loansToRepay.length;
        uint totalToRepay = 0;
        uint i = 0;
        while(i<length){
            totalToRepay += _repay(loansToRepay[i]);
            unchecked {
                i++;
            }
        }
        _balances[msg.sender] -= length;
        payable(msg.sender).sendValue(msg.value - totalToRepay); // overflow checks implictly check that amount is enough
    }

    // Liquidate expired loan
    function doEffectiveAltruism(Loan calldata loan, address to) external {
        require(liquidators[msg.sender] == true);
        uint loanId = getLoanId(loan.nft, loan.interest, loan.startTime, loan.borrowed);
        require(_exists(loanId), "loan closed");
        require(block.timestamp > (loan.startTime + maxLoanLength), "not expired");
        totalBorrowed -= loan.borrowed;
        _burn(loanId);
        nftContract.transferFrom(address(this), to, loan.nft);
    }

    function setOracle(address newValue) external onlyOwner {
        require(newValue != address(0), "oracle can't be 0");
        oracle = newValue;
    }

    function setMaxDailyBorrows(uint _maxDailyBorrows) external onlyOwner {
        maxDailyBorrows = _maxDailyBorrows;
    }

    function deposit() external payable onlyOwner {}

    function withdraw(uint amount) external onlyOwner {
        payable(msg.sender).sendValue(amount);
    }

    function checkOracle(
        uint216 price,
        uint256 deadline,
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
                        address(nftContract)
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

    function infoToRepayLoan(Loan calldata loan) view external returns (uint deadline, uint totalRepay, uint principal, uint interest, uint lateFees){
        deadline = loan.startTime + maxLoanLength;
        interest = ((block.timestamp - loan.startTime) * loan.interest * loan.borrowed) / 1e18;
        if(block.timestamp > deadline){
            lateFees = ((block.timestamp - deadline)*loan.borrowed)/(1 days);
        } else {
            lateFees = 0;
        }
        principal = loan.borrowed;
        totalRepay = principal + interest + lateFees;
    }

    function currentAnnualInterest(uint priceOfNextItem) external view returns (uint interest) {
        uint interestPerSecond;
        if(address(this).balance + totalBorrowed == 0){
            interestPerSecond = minimumInterest;
        } else {
            interestPerSecond = calculateInterest(priceOfNextItem);
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
        return string(abi.encodePacked(baseURI, Strings.toString(block.chainid), "/", Strings.toHexString(uint160(address(this)), 20), "/", Strings.toHexString(uint160(address(nftContract)), 20), "/"));
    }

    function setMaxPrice(uint newMaxPrice) external onlyOwner {
        maxPrice = newMaxPrice;
    }

    function changeInterest(uint _maxInterestPerEthPerSecond, uint _minimumInterest) external onlyOwner {
        maxVariableInterestPerEthPerSecond = _maxInterestPerEthPerSecond;
        minimumInterest = _minimumInterest;
    }

    function changeLTV(uint _ltv) external onlyOwner {
        ltv = _ltv;
    }

    function addLiquidator(address liq) external onlyOwner {
        liquidators[liq] = true;
        emit LiquidatorAdded(liq);
    }

    function removeLiquidator(address liq) external onlyOwner {
        liquidators[liq] = false;
        emit LiquidatorRemoved(liq);
    }

    function emergencyShutdown() external {
        require(msg.sender == factory);
        maxPrice = 0; // prevents new borrows
    }

    fallback() external {
        // money can still be received through self-destruct, which makes it possible to change balance without calling updateInterest, but if
        // owner does that -> they are lowering the money they earn through interest
        // debtor does that -> they always lose money because all loans are < 2 weeks
        revert();
    }
}
