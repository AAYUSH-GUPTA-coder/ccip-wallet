// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {Helper} from "./Helper.sol";
import {CcipWallet} from "../src/CcipWallet.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

contract DeployBasicTokenSender is Script, Helper {
    function run(SupportedNetworks source) external {
        uint256 senderPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(senderPrivateKey);

        (address router, address linkToken, , ) = getConfigFromNetwork(source);

        CcipWallet basicTokenSender = new CcipWallet(router, linkToken);

        console.log(
            "Basic Token Sender deployed on ",
            networks[source],
            "with address: ",
            address(basicTokenSender)
        );

        vm.stopBroadcast();
    }
}
