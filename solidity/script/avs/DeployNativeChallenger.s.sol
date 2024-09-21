// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import {NativeChallenger} from "../../contracts/avs/NativeChallenger.sol";
import {IMailbox} from "../../contracts/interfaces/IMailbox.sol";

/**
 * forge script script/avs/DeployNativeChallenger.s.sol --rpc-url $RPC_ROOTSTOCK --private-key $PRIVATE_KEY --broadcast --verify --verifier blockscout --verifier-url $BLOCKSCOUT_URL --legacy -vvvv
 */
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

    // function run() external {
    //     // Address of the deployed NativeChallenger contract
    //     address deployedNativeChallenger = 0x0163EE73720988ae1bD8816Fa5Cb586633a69b65;

    //     // Create an instance of the NativeChallenger contract
    //     NativeChallenger challenger = NativeChallenger(deployedNativeChallenger);

    //     // Start broadcasting transactions
    //     vm.startBroadcast();
    //     address mailboxAddr = challenger.getMailboxAddr();
    //     // Stop broadcasting transactions
    //     vm.stopBroadcast();

    //     // Log the result
    //     console.log("Mailbox address:", mailboxAddr);
    // }
}
