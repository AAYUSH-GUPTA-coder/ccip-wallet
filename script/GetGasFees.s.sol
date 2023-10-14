// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {Helper} from "./Helper.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.0/token/ERC20/IERC20.sol";

contract CCIPTokenTransfer is Script, Helper {
    function run(
        SupportedNetworks source,
        SupportedNetworks destination,
        address receiver,
        address tokenToSend,
        uint256 amount,
        PayFeesIn payFeesIn
    ) external returns (uint256 fees) {
        uint256 senderPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(senderPrivateKey);

        (address sourceRouter, address linkToken, , ) = getConfigFromNetwork(
            source
        );
        (, , , uint64 destinationChainId) = getConfigFromNetwork(destination);

        Client.EVMTokenAmount[]
            memory tokensToSendDetails = new Client.EVMTokenAmount[](1);
        Client.EVMTokenAmount memory tokenToSendDetails = Client
            .EVMTokenAmount({token: tokenToSend, amount: amount});

        tokensToSendDetails[0] = tokenToSendDetails;

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: "",
            tokenAmounts: tokensToSendDetails,
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 0, strict: false})
            ),
            feeToken: payFeesIn == PayFeesIn.LINK ? linkToken : address(0)
        });

        fees = IRouterClient(sourceRouter).getFee(destinationChainId, message);

        console.log("Fees for this transcation is");
        console.log(fees);

        vm.stopBroadcast();
    }
}

// forge script ./script/GetGasFees.s.sol -vvv --broadcast --rpc-url avalancheFuji --sig "run(uint8,uint8,address,address,uint256,uint8)" -- 2 0 0x16fA7AEb965b7292E1b7B140D6bcd849511cC343 0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846 100 0
