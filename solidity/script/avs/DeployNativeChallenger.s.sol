// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import {NativeChallenger} from "../../contracts/avs/NativeChallenger.sol";
import {IMailbox} from "../../contracts/interfaces/IMailbox.sol";

/**
 * forge script script/avs/DeployNativeChallenger.s.sol --rpc-url $RPC_ROOTSTOCK --private-key $PRIVATE_KEY --broadcast --verify --verifier blockscout --verifier-url $BLOCKSCOUT_URL --legacy -vvvv
 */
/// @notice Script to deploy and invoke a NativeChallenger on RootStock
contract DeployNativeChallenger is Script, Test {
    NativeChallenger public nativeChallenger;
    IMailbox public mailbox =
        IMailbox(0xCfA3E807DEF506Db480328cB975fC9108eb59e52);

    function run() external {
        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy NativeChallenger
        nativeChallenger = new NativeChallenger();
        nativeChallenger.setMailbox(mailbox);

        console.log("NativeChallenger deployed at:", address(nativeChallenger));

        // Stop broadcasting transactions
        vm.stopBroadcast();
    }

    /*function run() external {
        // Address of the deployed NativeChallenger contract
        //address deployedNativeChallengerSepolia = 0x0163EE73720988ae1bD8816Fa5Cb586633a69b65;
        address deployedNativeChallenger = 0x6eF12190b6aC5c4929652DDa05F21b86bee2c9E9;

        // Create an instance of the NativeChallenger contract
        NativeChallenger challenger = NativeChallenger(deployedNativeChallenger);

        // Start broadcasting transactions
        vm.startBroadcast();
        //challenger.setRemoteChallenger(0xCaDE4a9F4F06c10353c06920fBE055976D000943);
        challenger.simulateFraud();
        //address mailboxAddr = challenger.getMailboxAddr();
        //address remoteChallengerAddr = challenger.remoteChallenger();
        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Log the result
        //console.log("Mailbox address:", mailboxAddr);
        //console.log("RemoteChallenger addr", remoteChallengerAddr);
    }*/
}
