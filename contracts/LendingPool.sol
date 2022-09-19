//SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./libs/ERC721A.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract LendingPool is Ownable, ERC721A {
    using Address for address payable;

    struct Loan {
        uint nft;
        uint startTime;
        uint startInterestSum;
        uint borrowed;
    }

    IERC721 public immutable nftContract;
    uint256 public constant maxLoanLength = 2 weeks;
    uint256 public constant maxInterestPerEthPerSecond = 25367833587; // ~ 0.8 ether / 1 years;
    uint256 public maxPrice;
    address public oracle;
    uint public sumInterestPerEth = 0;
    uint public lastUpdate;
    uint public totalBorrowed = 0;
    mapping(uint=>Loan) public loans;
    string private baseURI = "https://api.tubbysea.com/nft/ethereum/";
    uint maxDailyBorrows; // IMPORTANT: an attacker can borrow 1.5 of this limit if they prepare beforehand
    uint currentDailyBorrows;
    uint lastUpdateDailyBorrows;
    address[] public liquidators;

    constructor(address _oracle, uint _maxPrice, address _nftContract, uint _maxDailyBorrows) ERC721A("TubbyLoan", "TL") {
        oracle = _oracle;
        maxPrice = _maxPrice;
        nftContract = IERC721(_nftContract);
        lastUpdate = block.timestamp;
        maxDailyBorrows = _maxDailyBorrows;
        lastUpdateDailyBorrows = block.timestamp;
    }

    // amountInThisTx -> msg.value if payable method, 0 otherwise
    modifier updateInterest(uint amountInThisTx) {
        uint elapsed = block.timestamp - lastUpdate;
        // this can't overflow
        // if we assume elapsed = 10 years = 10*365*24*3600 = 315360000
        // and totalBorrowed = 1M eth = 1e6*1e18 = 1e24
        // then that's only 142.52 bits, way lower than the 256 bits required for it to overflow.
        // There's one attack where you could blow up totalBorrowed by cycling borrows,
        // but since this requires a tubby each time it can only be done 20k times, which only increase bits by 14.28 -> still safu
        // `address(this).balance - amountInThisTx` can never underflow because amountInThisTx is always 0 or msg.value, both of which are always < address(this).balance 
        sumInterestPerEth += (elapsed * totalBorrowed * maxInterestPerEthPerSecond) / (address(this).balance - amountInThisTx + totalBorrowed + 1); // +1 prevents divisions by 0
        lastUpdate = block.timestamp;
        _;
    }

    function addDailyBorrows(uint toAdd) internal {
        uint elapsed = block.timestamp - lastUpdateDailyBorrows;
        currentDailyBorrows = (currentDailyBorrows - Math.min((maxDailyBorrows*elapsed)/(1 days), currentDailyBorrows)) + toAdd;
        require(currentDailyBorrows < maxDailyBorrows, "max daily borrow");
        lastUpdateDailyBorrows = block.timestamp;
    }

    function _borrow(
        uint nftId,
        uint256 price,
        uint index) internal {
        require(nftContract.ownerOf(nftId) == msg.sender, "not owner");
        loans[_nextTokenId() + index] = Loan(nftId, block.timestamp, sumInterestPerEth, price);
        nftContract.transferFrom(msg.sender, address(this), nftId);
    }

    function borrow(
        uint[] calldata nftId,
        uint256 price,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s) external updateInterest(0) {
        checkOracle(price, deadline, v, r, s);
        uint length = nftId.length;
        totalBorrowed += price * length;
        for(uint i=0; i<length; i++){
            _borrow(nftId[i], price, i);
        }
        uint borrowedNow = price * length;
        addDailyBorrows(borrowedNow);
        _mint(msg.sender, length);
        payable(msg.sender).sendValue(borrowedNow);
    }

    function _repay(uint loanId) internal returns (uint) {
        require(ownerOf(loanId) == msg.sender, "not owner");
        Loan storage loan = loans[loanId];
        uint sinceLoanStart = block.timestamp - loan.startTime;
        uint interest = ((sumInterestPerEth - loan.startInterestSum) * loan.borrowed) / 1e18;
        if(sinceLoanStart > maxLoanLength){
            uint loanEnd = loan.startTime + maxLoanLength;
            interest += ((block.timestamp - loanEnd)*loan.borrowed)/(1 days);
        }
        _burn(loanId);
        totalBorrowed -= loan.borrowed;
        nftContract.transferFrom(address(this), msg.sender, loan.nft);

        if(sinceLoanStart < (1 days)){
            uint until24h;
            unchecked {
                until24h = (1 days) - sinceLoanStart;
            }
            currentDailyBorrows = currentDailyBorrows - Math.min((loan.borrowed*until24h)/(1 days), currentDailyBorrows);
        }

        return interest + loan.borrowed;
    }

    function repay(uint[] calldata loanIds) external payable updateInterest(msg.value) {
        uint length = loanIds.length;
        uint totalToRepay = 0;
        addDailyBorrows(0); // todo: this is path dependent because of the min() but maybe if we remove this it's still ok?
        for(uint i=0; i<length; i++){
            totalToRepay += _repay(loanIds[i]);
        }
        payable(msg.sender).sendValue(msg.value - totalToRepay); // overflow checks implictly check that amount is enough
    }

    function claw(uint loanId, uint liquidatorIndex) external updateInterest(0) {
        require(liquidators[liquidatorIndex] == msg.sender);
        Loan storage loan = loans[loanId];
        require(_exists(loanId), "loan closed");
        require(block.timestamp > (loan.startTime + maxLoanLength), "not expired");
        _burn(loanId);
        totalBorrowed -= loan.borrowed;
        nftContract.transferFrom(address(this), msg.sender, loan.nft);
    }

    function setOracle(address newValue) external onlyOwner {
        oracle = newValue;
    }

    function setMaxDailyBorrows(uint _maxDailyBorrows) external onlyOwner {
        maxDailyBorrows = _maxDailyBorrows;
    }

    function deposit() external payable onlyOwner updateInterest(msg.value) {}

    function withdraw(uint amount) external onlyOwner updateInterest(0) {
        payable(msg.sender).sendValue(amount);
    }

    function checkOracle(
        uint256 price,
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
                        "\x19Ethereum Signed Message:\n84",
                        price,
                        deadline,
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

    function currentSumInterestPerEth() view public returns (uint) {
        uint elapsed = block.timestamp - lastUpdate;
        return sumInterestPerEth + (elapsed * totalBorrowed * maxInterestPerEthPerSecond) / (address(this).balance + totalBorrowed + 1);
    }

    function infoToRepayLoan(uint loanId) view external returns (uint deadline, uint totalRepay, uint principal, uint interest, uint lateFees){
        Loan storage loan = loans[loanId];
        deadline = loan.startTime + maxLoanLength;
        interest = ((currentSumInterestPerEth() - loan.startInterestSum) * loan.borrowed) / 1e18;
        if(block.timestamp > deadline){
            lateFees = ((block.timestamp - deadline)*loan.borrowed)/(1 days);
        } else {
            lateFees = 0;
        }
        principal = loan.borrowed;
        totalRepay = principal + interest + lateFees;
    }

    function currentAnnualInterest(uint priceOfNextItem) external view returns (uint interest) {
        uint borrowed = priceOfNextItem + totalBorrowed;
        return (365 days * borrowed * maxInterestPerEthPerSecond) / (address(this).balance + totalBorrowed + 1);
    }

    function _baseURI() internal view override returns (string memory) {
        return string(abi.encodePacked(baseURI, Strings.toHexString(uint160(address(this)), 20), "/", Strings.toHexString(uint160(address(nftContract)), 20), "/"));
    }

    function setMaxPrice(uint newMaxPrice) external onlyOwner {
        maxPrice = newMaxPrice;
    }

    function addLiquidator(address liq) external onlyOwner {
        liquidators.push(liq);
    }

    function removeLiquidator(uint index) external onlyOwner {
        liquidators[index] = address(0);
    }

    function liquidatorsLength() external view returns (uint){
        return liquidators.length;
    }

    function setBaseURI(string memory newBaseURI) external onlyOwner {
        baseURI = newBaseURI;
    }

    fallback() external {
        // money can still be received through self-destruct, which makes it possible to change balance without calling updateInterested, but if
        // owner does that -> they are lowering the money they earn through interest
        // debtor does that -> they always lose money because all loans are < 2 weeks
        revert();
    }
}
