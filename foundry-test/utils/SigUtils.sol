// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

contract SigUtils {
    function getDigest(
        uint216 price,
        uint256 deadline,
        address nftContract,
        uint256 chainId
    ) public pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n111",
                    price,
                    deadline,
                    chainId,
                    nftContract
                )
            );
    }
}
