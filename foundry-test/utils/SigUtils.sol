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

    function isValidSignature(
        uint216 price,
        uint256 deadline,
        address nftContract,
        uint256 chainId,
        uint8 v,
        bytes32 r,
        bytes32 s,
        address signer
    ) public pure returns (bool) {
        address recoveredAddress = ecrecover(
            keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n111",
                    price,
                    deadline,
                    chainId,
                    nftContract
                )
            ),
            v,
            r,
            s
        );
        return recoveredAddress != address(0) && recoveredAddress == signer;
    }
}
