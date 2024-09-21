// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0;

/*@@@@@@@       @@@@@@@@@
 @@@@@@@@@       @@@@@@@@@
  @@@@@@@@@       @@@@@@@@@
   @@@@@@@@@       @@@@@@@@@
    @@@@@@@@@@@@@@@@@@@@@@@@@
     @@@@@  HYPERLANE  @@@@@@@
    @@@@@@@@@@@@@@@@@@@@@@@@@
   @@@@@@@@@       @@@@@@@@@
  @@@@@@@@@       @@@@@@@@@
 @@@@@@@@@       @@@@@@@@@
@@@@@@@@@       @@@@@@@@*/

import {Router} from "../client/Router.sol";
import {IRemoteChallenger} from "../interfaces/avs/IRemoteChallenger.sol";
import {HyperlaneServiceManager} from "./HyperlaneServiceManager.sol";
import "../AttributeCheckpointFraud.sol";

/**
 * @dev Contract on the Ethereum L1 (Sepolia) chain, which receives a fraud proof and slash the operator
 */
contract NativeChallenger is IRemoteChallenger, Router {
    HyperlaneServiceManager public hsm;

    constructor(address _mailbox, address _hsm) Router(_mailbox) {
        hsm = HyperlaneServiceManager(_hsm);
    }

    function _handle(
        uint32 _origin,
        bytes32 _sender,
        bytes calldata _message
    ) internal override {
        require(
            _isRemoteRouter(_origin, _sender),
            "Invalid sender. It has to be a NativeChallenger"
        );

        // Decode the message with metadata, "unwrapping" the user's message body
        (address _operator, bytes32 _timestamp, uint8 _fraudType) = abi.decode(
            _message,
            (address, bytes32, uint8)
        );

        /// TODO: Depending on the fraud type, determine a slashing percentage

        handleChallenge(_operator);
    }

    /// @notice Not relevant in the frame of that hackathon
    function challengeDelayBlocks() external pure returns (uint256) {
        return 0;
    }

    /// @notice Handles a challenge for an operator
    /// @param operator The address of the operator
    function handleChallenge(address operator) public {
        hsm.freezeOperator(operator);
    }
}
