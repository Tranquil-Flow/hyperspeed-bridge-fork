// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {TREE_DEPTH} from "./libs/Merkle.sol";
import {CheckpointLib, Checkpoint} from "./libs/CheckpointLib.sol";
import {CheckpointFraudProofs} from "./CheckpointFraudProofs.sol";

enum FraudType {
    Whitelist,
    Premature,
    MessageId,
    Root
}

struct Attribution {
    address signer;
    // for comparison with staking epoch
    uint48 timestamp;
    FraudType fraudType;
}

/**
 * @title AttributeCheckpointFraud
 * @dev The AttributeCheckpointFraud contract is used to attribute fraud to a specific ECDSA checkpoint signer.
 */
contract AttributeCheckpointFraud is Ownable {
    using CheckpointLib for Checkpoint;
    using Address for address;

    CheckpointFraudProofs public immutable checkpointFraudProofs =
        new CheckpointFraudProofs();

    mapping(address => bool) public merkleTreeWhitelist;

    mapping(address signer => mapping(bytes32 digest => Attribution))
        internal _attributions;

    function _recover(
        Checkpoint calldata checkpoint,
        bytes calldata signature
    ) internal pure returns (address signer, bytes32 digest) {
        digest = checkpoint.digest();
        signer = ECDSA.recover(digest, signature);
    }

    function _attribute(
        bytes calldata signature,
        Checkpoint calldata checkpoint,
        FraudType fraudType
    ) internal {
        (address signer, bytes32 digest) = _recover(checkpoint, signature);
        require(
            _attributions[signer][digest].timestamp == 0,
            "fraud already attributed to signer for digest"
        );
        _attributions[signer][digest] = Attribution({
            signer: signer,
            fraudType: fraudType,
            timestamp: uint48(block.timestamp)
        });
    }

    function attributions(
        Checkpoint calldata checkpoint,
        bytes calldata signature
    ) public view returns (Attribution memory) {
        (address signer, bytes32 digest) = _recover(checkpoint, signature);
        return _attributions[signer][digest];
    }

    function whitelist(address merkleTree) external onlyOwner {
        require(
            merkleTree.isContract(),
            "merkle tree must be a valid contract"
        );
        merkleTreeWhitelist[merkleTree] = true;
    }

    function attributeWhitelist(
        Checkpoint calldata checkpoint,
        bytes calldata signature
    ) public {
        require(
            checkpointFraudProofs.isLocal(checkpoint),
            "checkpoint must be local"
        );

        require(
            !merkleTreeWhitelist[checkpoint.merkleTreeAddress()],
            "merkle tree is whitelisted"
        );

        _attribute(signature, checkpoint, FraudType.Whitelist);
    }

    function attributePremature(
        Checkpoint calldata checkpoint,
        bytes calldata signature
    ) public {
        require(
            checkpointFraudProofs.isPremature(checkpoint),
            "checkpoint must be premature"
        );

        _attribute(signature, checkpoint, FraudType.Premature);
    }

    function attributeMessageId(
        Checkpoint calldata checkpoint,
        bytes32[TREE_DEPTH] calldata proof,
        bytes32 actualMessageId,
        bytes calldata signature
    ) public {
        require(
            checkpointFraudProofs.isFraudulentMessageId(
                checkpoint,
                proof,
                actualMessageId
            ),
            "checkpoint must have fraudulent message ID"
        );

        _attribute(signature, checkpoint, FraudType.MessageId);
    }

    function attributeRoot(
        Checkpoint calldata checkpoint,
        bytes32[TREE_DEPTH] calldata proof,
        bytes calldata signature
    ) public {
        require(
            checkpointFraudProofs.isFraudulentRoot(checkpoint, proof),
            "checkpoint must have fraudulent root"
        );

        _attribute(signature, checkpoint, FraudType.Root);
    }
}
