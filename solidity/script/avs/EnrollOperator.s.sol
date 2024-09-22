// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import {HyperlaneServiceManager} from "../../contracts/avs/HyperlaneServiceManager.sol";
import {Slasher} from "../../contracts/eigenLayerMocks/Slasher.sol";
import {IRemoteChallenger} from "../../contracts/interfaces/avs/IRemoteChallenger.sol";

/**
 * forge script script/avs/DeployRemoteChallenger.s.sol --rpc-url $RPC_HOLESKY --private-key $OPERATOR_PRIVATE_KEY --broadcast -vvvv
 */
/// Script to enroll an operator into an challenger and giving access to its stake
contract EnrollOperator is Script, Test {
    HyperlaneServiceManager public hsm =
        HyperlaneServiceManager(0x722d2c3c18f161edF8778A2Dd4F5893A3dA89540);
    Slasher public slasher =
        Slasher(0xFb91dd18A1Ac21e6dEB70FD242410fD96aea9c8C);
    IRemoteChallenger public remoteChallenger =
        IRemoteChallenger(0xCaDE4a9F4F06c10353c06920fBE055976D000943);

    uint256 deployerPrivateKey;

    function run() external {
        // Start broadcasting transactions
        vm.startBroadcast();

        // Enroll in challenger
        hsm.enrollIntoChallenger(remoteChallenger);
        hsm.startUnenrollment(remoteChallenger);
        // Register operator and send 0.5 ether
        slasher.registerOperator{value: 0.5 ether}(msg.sender);

        // Stop broadcasting transactions
        vm.stopBroadcast();
    }
}
