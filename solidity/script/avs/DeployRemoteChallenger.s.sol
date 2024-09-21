// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import {RemoteChallenger} from "../../contracts/avs/RemoteChallenger.sol";
import {Slasher} from "../../contracts/eigenLayerMocks/Slasher.sol";

/**
 * forge script script/avs/DeployRemoteChallenger.s.sol --rpc-url $RPC_HOLESKY --private-key $DEPLOYER_PRIVATE_KEY --broadcast --etherscan-api-key $ETHERSCAN_API_KEY --verify -vvvv
 */
/// @notice Script to deploy a remote challenger and a mock slasher
contract DeployRemoteChallenger is Script, Test {
    address public hsm = 0x722d2c3c18f161edF8778A2Dd4F5893A3dA89540;
    address public mailbox = 0x46f7C5D896bbeC89bE1B19e4485e59b4Be49e9Cc;

    uint32 public domain = 31;
    bytes32 public router =
        bytes32(uint256(uint160(0x0163EE73720988ae1bD8816Fa5Cb586633a69b65)));

    RemoteChallenger public remoteChallenger;
    Slasher public slasher;

    function run() external {
        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy NativeChallenger
        remoteChallenger = new RemoteChallenger(mailbox, hsm);
        slasher = new Slasher();

        // Enroll Remote Router
        remoteChallenger.enrollRemoteRouter(domain, router);

        console.log("RemoteChallenger deployed at:", address(remoteChallenger));
        console.log("Slasher deployed at:", address(slasher));

        // Stop broadcasting transactions
        vm.stopBroadcast();
    }
}
