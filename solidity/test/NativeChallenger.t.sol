// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "forge-std/Test.sol";
import {NativeChallenger} from "../contracts/avs/NativeChallenger.sol";
import {CheckpointLib, Checkpoint} from "../contracts/libs/CheckpointLib.sol";
import {CheckpointFraudProofs} from "../contracts/AttributeCheckpointFraud.sol";

contract MockMerkleTreeHook {
    uint32 public localDomain;

    constructor(uint32 _localDomain) {
        localDomain = _localDomain;
    }
}

contract NativeChallengerTest is Test {
    using CheckpointLib for Checkpoint;

    NativeChallenger public challenger;

    CheckpointFraudProofs fraudProofs;
    MockMerkleTreeHook mockMerkleTree;

    uint256 private privateKey = 0xA11CE;
    address public publicKey = vm.addr(privateKey);

    function setUp() public {
        challenger = new NativeChallenger();

        uint32 testOrigin = 1;
        mockMerkleTree = new MockMerkleTreeHook(testOrigin);
    }

    function test_nativeChallenger() public {
        // Create Checkpoint
        Checkpoint memory checkpoint = Checkpoint({
            origin: 1,
            merkleTree: bytes32(uint256(uint160(address(mockMerkleTree)))),
            root: bytes32(uint256(1)),
            index: 1,
            messageId: bytes32(uint256(2))
        });

        //assertTrue(fraudProofs.isLocal(checkpoint));
        //console.log("isLocal true");

        // Calculate digest
        bytes32 digest = checkpoint.digest();
        // Sign the digest
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        // Encode the signature
        bytes memory signature = abi.encodePacked(r, s, v);

        // Recover the signer
        address signer = ECDSA.recover(digest, signature);

        assertEq(signer, publicKey);

        challenger.challengePremature(publicKey, checkpoint, signature);
    }
}
