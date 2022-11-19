// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./utils/SigUtils.sol";

contract OracleTest is Test {
    address constant NFT_CONTRACT = 0xf5de760f2e916647fd766B4AD9E85ff943cE3A2b; // MultiFaucet NFT
    uint216 constant PRICE = 0.01 ether;
    uint256 DEADLINE;

    uint256 oraclePrivateKey = 0x01;
    address oracle = vm.addr(oraclePrivateKey);

    uint256 chainId;
    SigUtils sigUtils;

    function setUp() public {
        DEADLINE = (block.timestamp / 1000) + 3600 * 24 * 30; // +1 month
        sigUtils = new SigUtils();
        vm.chainId(5); // Ethereum Goerli
    }

    function test_GenerateSignatureForGoerli() public {
        (uint8 v, bytes32 r, bytes32 s) = _generateSignature();
        emit log_string(Strings.toHexString(NFT_CONTRACT));
        emit log_uint(PRICE);
        emit log_uint(DEADLINE);
        emit log_uint(v);
        emit log_bytes32(r);
        emit log_bytes32(s);
        assertEq(
            sigUtils.isValidSignature(
                PRICE,
                DEADLINE,
                NFT_CONTRACT,
                block.chainid,
                v,
                r,
                s,
                oracle
            ),
            true
        );
    }

    function _generateSignature()
        private
        returns (
            uint8 v,
            bytes32 r,
            bytes32 s
        )
    {
        bytes32 digest = sigUtils.getDigest(
            PRICE,
            DEADLINE,
            NFT_CONTRACT,
            block.chainid
        );
        (v, r, s) = vm.sign(oraclePrivateKey, digest);
    }
}
