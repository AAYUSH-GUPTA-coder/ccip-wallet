/**
 * @title A smart contract wallet that allows users to transfer their tokens to a different account in a different or the same chain in a single execution using CCIP
 * @author Aayush Gupta Twitter: @Aayush_gupta_ji
 * contract address : 0xaEfea6a5a5D33976920aD4cb880edb188d85ea53 (old contract address without Balance getter functions)
 */

// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.0/token/ERC20/IERC20.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";

contract CcipWallet is OwnerIsCreator {
    ///////////////////////////////////////////
    //////      ERRORS                   //////
    //////////////////////////////////////////
    // Custom errors to provide more descriptive revert messages.
    error CcipWallet__NotEnoughBalance(
        uint256 currentBalance,
        uint256 calculatedFees
    ); // Used to make sure contract has enough balance to cover the fees.
    error CcipWallet__NothingToWithdraw(); // Used when trying to withdraw Ether but there's nothing to withdraw.
    error CcipWallet__FailedToWithdrawEth(
        address owner,
        address target,
        uint256 value
    ); // Used when the withdrawal of Ether fails.
    error CcipWallet__DestinationChainNotWhitelisted(
        uint64 destinationChainSelector
    ); // Used when the destination chain has not been whitelisted by the contract owner.

    ///////////////////////////////////////////
    //////      EVENTS                  //////
    //////////////////////////////////////////
    /**
     * @notice Event emitted when the tokens are transferred to an account on another chain.
     * @param messageId The unique ID of the message.
     * @param destinationChainSelector The chain selector of the destination chain.
     * @param receiver The address of the receiver on the destination chain.
     * @param token The token address that was transferred.
     * @param tokenAmount The token amount that was transferred.
     * @param feeToken the token address used to pay CCIP fees.
     * @param fees The fees paid for sending the message.
     */
    event TokensTransferred(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address receiver,
        address token,
        uint256 tokenAmount,
        address feeToken,
        uint256 fees
    );

    /**
     * @notice event emitted when NATIVE token is received.
     * @param sender address of the sender
     * @param amount amount of native token received
     * @param data The data that was sent with the transaction
     */
    event ReceivedNativeToken(address indexed sender, uint amount, bytes data);

    ///////////////////////////////////////////
    //////      MAPPING                  //////
    //////////////////////////////////////////

    // Mapping to keep track of whitelisted destination chains.
    mapping(uint64 => bool) public whitelistedChains;

    IRouterClient router;

    LinkTokenInterface linkToken;

    /**
     * @notice Constructor initializes the contract with the router address and LINK Token address
     * @param _router The address of the router contract.
     * @param _link The address of the link contract.
     */
    constructor(address _router, address _link) {
        router = IRouterClient(_router);
        linkToken = LinkTokenInterface(_link);
    }

    /**
     * @dev Modifier that checks if the chain with the given destinationChainSelector is whitelisted.
     * @param _destinationChainSelector The selector of the destination chain.
     */
    modifier onlyWhitelistedChain(uint64 _destinationChainSelector) {
        if (!whitelistedChains[_destinationChainSelector])
            revert CcipWallet__DestinationChainNotWhitelisted(
                _destinationChainSelector
            );
        _;
    }

    ///////////////////////////////////////////
    //////      Setter Functions        //////
    //////////////////////////////////////////

    /**
     * @dev Whitelists a chain for transactions.
     * @notice This function can only be called by the owner.
     * @param _destinationChainSelector The selector of the destination chain to be whitelisted.
     */
    function whitelistChain(
        uint64 _destinationChainSelector
    ) external onlyOwner {
        whitelistedChains[_destinationChainSelector] = true;
    }

    /**
     * @dev Denylists a chain for transactions.
     * @notice This function can only be called by the owner.
     * @param _destinationChainSelector The selector of the destination chain to be denylisted.
     */
    function denylistChain(
        uint64 _destinationChainSelector
    ) external onlyOwner {
        whitelistedChains[_destinationChainSelector] = false;
    }

    /**
     * @notice Transfer tokens to receiver on the destination chain.
     * @notice CCIP Fees are paid in LINK.
     * @notice the token must be in the list of supported tokens.
     * @notice This function can only be called by the owner.
     * @dev Assumes your contract has sufficient LINK tokens to pay for the fees.
     *
     * @param _destinationChainSelector The identifier (aka selector) for the destination blockchain.
     * @param _receiver The address of the recipient on the destination blockchain.
     * @param _token token address.
     * @param _amount token amount.
     * @return messageId The ID of the message that was sent.
     */
    function transferTokensPayLINK(
        uint64 _destinationChainSelector,
        address _receiver,
        address _token,
        uint256 _amount
    )
        external
        onlyOwner
        onlyWhitelistedChain(_destinationChainSelector)
        returns (bytes32 messageId)
    {
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        //  address(linkToken) means fees are paid in LINK
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
            _receiver,
            _token,
            _amount,
            address(linkToken)
        );

        // Get the fee required to send the message
        uint256 fees = router.getFee(_destinationChainSelector, evm2AnyMessage);

        if (fees > linkToken.balanceOf(address(this)))
            revert CcipWallet__NotEnoughBalance(
                linkToken.balanceOf(address(this)),
                fees
            );

        // approve the Router to transfer LINK tokens on contract's behalf. It will spend the fees in LINK
        linkToken.approve(address(router), fees);

        // approve the Router to spend tokens on contract's behalf. It will spend the amount of the given token
        IERC20(_token).approve(address(router), _amount);

        // Send the message through the router and store the returned message ID
        messageId = router.ccipSend(_destinationChainSelector, evm2AnyMessage);

        // Emit an event with message details
        emit TokensTransferred(
            messageId,
            _destinationChainSelector,
            _receiver,
            _token,
            _amount,
            address(linkToken),
            fees
        );

        // Return the message ID
        return messageId;
    }

    /**
     * @notice Transfer tokens to receiver on the destination chain.
     * @notice Pay in native gas such as ETH on Ethereum or MATIC on Polgon.
     * @notice the token must be in the list of supported tokens.
     *  @notice This function can only be called by the owner.
     *  @dev Assumes your contract has sufficient native gas like ETH on Ethereum or MATIC on Polygon.
     * @param _destinationChainSelector The identifier (aka selector) for the destination blockchain.
     * @param _receiver The address of the recipient on the destination blockchain.
     * @param _token token address.
     * @param _amount token amount.
     * @return messageId The ID of the message that was sent.
     */
    function transferTokensPayNative(
        uint64 _destinationChainSelector,
        address _receiver,
        address _token,
        uint256 _amount
    )
        external
        onlyOwner
        onlyWhitelistedChain(_destinationChainSelector)
        returns (bytes32 messageId)
    {
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        // address(0) means fees are paid in native gas
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
            _receiver,
            _token,
            _amount,
            address(0)
        );

        // Get the fee required to send the message
        uint256 fees = router.getFee(_destinationChainSelector, evm2AnyMessage);

        if (fees > address(this).balance)
            revert CcipWallet__NotEnoughBalance(address(this).balance, fees);

        // approve the Router to spend tokens on contract's behalf. It will spend the amount of the given token
        IERC20(_token).approve(address(router), _amount);

        // Send the message through the router and store the returned message ID
        messageId = router.ccipSend{value: fees}(
            _destinationChainSelector,
            evm2AnyMessage
        );

        // Emit an event with message details
        emit TokensTransferred(
            messageId,
            _destinationChainSelector,
            _receiver,
            _token,
            _amount,
            address(0),
            fees
        );

        // Return the message ID
        return messageId;
    }

    /**
     * @notice Construct a CCIP message.
     * @dev This function will create an EVM2AnyMessage struct with all the necessary information for tokens transfer.
     * @param _receiver The address of the receiver.
     * @param _token The token to be transferred.
     * @param _amount The amount of the token to be transferred.
     * @param _feeTokenAddress The address of the token used for fees. Set address(0) for native gas.
     * @return Client.EVM2AnyMessage Returns an EVM2AnyMessage struct which contains information for sending a CCIP message.
     */
    function _buildCCIPMessage(
        address _receiver,
        address _token,
        uint256 _amount,
        address _feeTokenAddress
    ) internal pure returns (Client.EVM2AnyMessage memory) {
        // Set the token amounts
        Client.EVMTokenAmount[]
            memory tokenAmounts = new Client.EVMTokenAmount[](1);
        Client.EVMTokenAmount memory tokenAmount = Client.EVMTokenAmount({
            token: _token,
            amount: _amount
        });
        tokenAmounts[0] = tokenAmount;
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(_receiver), // ABI-encoded receiver address
            data: "", // No data
            tokenAmounts: tokenAmounts, // The amount and type of token being transferred
            extraArgs: Client._argsToBytes(
                // Additional arguments, setting gas limit to 0 as we are not sending any data and non-strict sequencing mode
                Client.EVMExtraArgsV1({gasLimit: 0, strict: false})
            ),
            // Set the feeToken to a feeTokenAddress, indicating specific asset will be used for fees
            feeToken: _feeTokenAddress
        });
        return evm2AnyMessage;
    }

    /**
     * @notice fallback() function is called to receive NATIVE token if msg.data is NOT empty.
     */
    fallback() external payable {
        emit ReceivedNativeToken(msg.sender, msg.value, msg.data);
    }

    /**
     * @notice receive() function is called to receive NATIVE token if msg.data is empty
     */
    receive() external payable {
        emit ReceivedNativeToken(msg.sender, msg.value, "");
    }

    /**
     * @notice Allows the contract owner to withdraw the entire balance of Ether from the contract.
     * @dev This function reverts if there are no funds to withdraw or if the transfer fails. It should only be callable by the owner of the contract.
     * @param _beneficiary The address to which the Ether should be transferred.
     */
    function withdraw(address _beneficiary) external onlyOwner {
        // Retrieve the balance of this contract
        uint256 amount = address(this).balance;

        // Revert if there is nothing to withdraw
        if (amount == 0) revert CcipWallet__NothingToWithdraw();

        // Attempt to send the funds, capturing the success status and discarding any return data
        (bool sent, ) = _beneficiary.call{value: amount}("");

        // Revert if the send failed, with information about the attempted transfer
        if (!sent)
            revert CcipWallet__FailedToWithdrawEth(
                msg.sender,
                _beneficiary,
                amount
            );
    }

    /**
     * @notice Allows the owner of the contract to withdraw all tokens of a specific ERC20 token.
     * @dev This function reverts with a 'CcipWallet__NothingToWithdraw' error if there are no tokens to withdraw.
     * @param _beneficiary The address to which the tokens will be sent.
     * @param _token The contract address of the ERC20 token to be withdrawn.
     */
    function withdrawToken(
        address _beneficiary,
        address _token
    ) external onlyOwner {
        // Retrieve the balance of this contract
        uint256 amount = IERC20(_token).balanceOf(address(this));

        // Revert if there is nothing to withdraw
        if (amount == 0) revert CcipWallet__NothingToWithdraw();

        IERC20(_token).transfer(_beneficiary, amount);
    }

    /**
     * @notice Getter function to get the CCIP fees of the cross-chain transcation in LINK
     * @param _receiver The address of the recipient on the destination blockchain.
     * @param _token token address.
     * @param _amount token amount.
     * @return messageId The ID of the message that was sent.
     */
    function getCcipFeesLink(
        uint64 _destinationChainSelector,
        address _receiver,
        address _token,
        uint256 _amount
    )
        external
        view
        onlyWhitelistedChain(_destinationChainSelector)
        returns (uint256)
    {
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        // address(0) means fees are paid in native gas
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
            _receiver,
            _token,
            _amount,
            address(0)
        );

        return router.getFee(_destinationChainSelector, evm2AnyMessage);
    }

    /**
     * @notice Getter function to get the CCIP fees of the cross-chain transcation in LINK
     * @param _receiver The address of the recipient on the destination blockchain.
     * @param _token token address.
     * @param _amount token amount.
     * @return messageId The ID of the message that was sent.
     */
    function getCcipFeesToken(
        uint64 _destinationChainSelector,
        address _receiver,
        address _token,
        uint256 _amount
    )
        external
        view
        onlyWhitelistedChain(_destinationChainSelector)
        returns (uint256)
    {
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        //  address(linkToken) means fees are paid in LINK
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
            _receiver,
            _token,
            _amount,
            address(linkToken)
        );

        return router.getFee(_destinationChainSelector, evm2AnyMessage);
    }

    /**
     * @notice function to get the balance of ERC20 Tokens
     * @return token_balance of the smart contract
     */
    function getTokenBalance(address _token) external view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }
}
