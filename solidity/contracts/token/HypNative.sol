// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.0;

import {TokenRouter} from "./libs/TokenRouter.sol";
import {TokenMessage} from "./libs/TokenMessage.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// Interfaces for price feeds
interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

interface IUmbrellaFeeds {
    struct PriceData {
        uint128 price;
        uint32 timestamp;
        uint24 heartbeat;
    }

    function getPriceDataByName(
        string calldata _name
    ) external view returns (PriceData memory data);
}

interface IInsuranceFund {
    function liquidateForReorg(uint256 amount) external returns (bool);
}

/**
 * @title Hyperlane Native Token Router that extends ERC20 with remote transfer functionality.
 * @author Abacus Works
 * @dev Supply on each chain is not constant but the aggregate supply across all chains is.
 * @dev Hyperspeed Bridge: This is a combined version of HypNative for both Ethereum and Rootstock, allowing for:
 * - Bridging of native tokens across chains (i.e. deposit ETH on Ethereum and receive RBTC on Rootstock, and vice versa)
 * - Instant transfer of bridged assets, ignoring finality as long as the currently bridging amount does not exceed the insurance fund.
 * - Depositing of liquidity which is utilized by the contract for handling withdrawals and earns bridging fees.
 */
contract HypNative is TokenRouter, ReentrancyGuard {
    IInsuranceFund public insuranceFund;
    AggregatorV3Interface public chainlinkDataFeed;
    IUmbrellaFeeds public umbrellaFeeds;

    struct TransferRecord {
        uint256 amount; // The amount of USD value being bridged
        uint256 blockNumber; // The block number this transfer was initiated
    }

    struct ReorgedTransfer {
        uint256 amount; // The amount of USD value in the reorged transfer
        uint256 blockNumber; // The block number this transfer was initiated & reorged on
        uint256 originalIndex; // The original index of the transfer
    }

    struct PendingTransfer {
        uint256 amount; // The amount of USD value being bridged
        uint256 blockNumber; // The block number this transfer was initiated
    }

    mapping(uint32 chainID => mapping(uint256 transferID => TransferRecord))
        public transferRecords; //Stores all bridging transfers.
    mapping(uint32 => ReorgedTransfer[]) public reorgedTransfers; // Stores all reorged transfers.
    PendingTransfer[] public pendingTransfers; // Stores all pending transfers.

    uint256 public otherChainInsuranceFundAmount; // Stores the amount of USD value in the Insurance Fund on the other chain
    uint256 public otherChainAvailableLiquidity; // Stores the amount of USD value in the available liquidity on the other chain
    uint256 public pendingBridgeAmount; // The amount of USD value that is currently being bridged and has not reached finality.
    uint256 public constant FINALITY_PERIOD = 12; // The number of blocks required for finality.

    uint256 public nextTransferId; // The next transfer ID to be used

    uint256 public constant OUTBOUND_FEE_PERCENTAGE = 1; // 0.1% on outbound transfers
    uint256 public constant INBOUND_FEE_PERCENTAGE = 1; // 0.1% on inbound transfers
    uint256 public constant LIQUIDITY_PROVIDER_REWARD_SHARE = 80; // 80% of fees paid to liquidity providers
    uint256 public constant INSURANCE_FUND_REWARD_SHARE = 20; // 20% of fees paid to the Insurance Fund

    uint256 public totalLiquidityShares; // The total amount of shares, representing user liquidity deposits.
    uint256 public totalFees; // The total amount of outstanding fees collected by the bridge.
    mapping(address => uint256) public userLiquidityShares; // The amount of shares a user owns in the bridge liquidity
    mapping(address => uint256) public userFeeIndex; // The fee index for a user, representing when they last claimed their fees
    uint256 public feeIndex; // The current fee index, increases each time fees are distributed
    uint256 private constant PRECISION = 1e18;

    bool public isEthereum; // Determines whether this contract is deployed on Ethereum or Rootstock
    bool public networkSet; // Flag to ensure the network is set only once

    /**
     * @dev Emitted when native tokens are donated to the contract.
     * @param sender The address of the sender.
     * @param amount The amount of native tokens donated.
     */
    event Donation(address indexed sender, uint256 amount);
    event LiquidityDeposited(
        address indexed provider,
        uint256 assets,
        uint256 shares
    );
    event LiquidityWithdrawn(
        address indexed provider,
        uint256 assets,
        uint256 shares
    );

    /**
     * @dev Constructor for the HypNative contract.
     * @param _mailbox The address of the mailbox contract.
     */
    constructor(address _mailbox) TokenRouter(_mailbox) {}

    /**
     * @dev Sets whether the contract is deployed on Ethereum or Rootstock.
     * @param _isEthereum True if the contract is on Ethereum, false if on Rootstock.
     * @param _insuranceFund The address of the Insurance Fund contract.
     */
    function setNetwork(bool _isEthereum, address _insuranceFund) external {
        require(!networkSet, "Network already set");
        isEthereum = _isEthereum;
        networkSet = true;

        if (isEthereum) {
            // Ethereum Sepolia Chainlink Data Feed
            chainlinkDataFeed = AggregatorV3Interface(
                0x694AA1769357215DE4FAC081bf1f309aDC325306
            );
        } else {
            // Rootstock Testnet UmbrellaFeeds
            umbrellaFeeds = IUmbrellaFeeds(
                0x3F2254bc49d2d6e8422D71cB5384fB76005558A9
            );
        }

        insuranceFund = IInsuranceFund(_insuranceFund);
    }

    /**
     * @notice Initializes the Hyperlane router
     * @param _hook The post-dispatch hook contract.
     * @param _interchainSecurityModule The interchain security module contract.
     * @param _owner The owner of this contract.
     */
    function initialize(
        address _hook,
        address _interchainSecurityModule,
        address _owner
    ) public initializer {
        _MailboxClient_initialize(_hook, _interchainSecurityModule, _owner);
    }

    /**
     * @inheritdoc TokenRouter
     * @dev uses (`msg.value` - `_amount`) as hook payment and `msg.sender` as refund address.
     * @dev Calculates USD value of native token being bridged and sends this value cross chain.
     * @dev Checks if the amount being bridged is within the safe bridgeable amount.
     * @dev Takes the outbound bridging fee from the user and distributes to liquidity providers + Insurance Fund.
     */
    function transferRemote(
        uint32 _destination,
        bytes32 _recipient,
        uint256 _amount
    ) external payable virtual override returns (bytes32 messageId) {
        require(msg.value >= _amount, "Native: amount exceeds msg.value");
        uint256 _hookPayment = msg.value - _amount;

        // Take the outbound bridging fee
        uint256 fee = (_amount * OUTBOUND_FEE_PERCENTAGE) / 10000;
        uint256 amountAfterFee = _amount - fee;
        _distributeFees(fee);

        // Get the latest native token/USD price
        uint256 nativePrice = getLatestPrice();

        // Calculate the USD value of the native token being bridged
        uint256 _usdValue = (amountAfterFee * nativePrice) / 1e18;
        require(
            _usdValue <= otherChainAvailableLiquidity,
            "Insufficient liquidity on the destination chain"
        );

        // Checks if any transfers have reached finality and updates the pending bridge amount accordingly.
        _processFinalizedTransfers();

        // Checks the safe amount that can be currently bridged given the Insurance Fund and the pending bridged amount awaiting finality.
        uint256 safeBridgeableAmount = getInsuranceFundAmount() -
            pendingBridgeAmount;
        require(
            _usdValue <= safeBridgeableAmount,
            "Exceeds safe bridgeable amount"
        );

        // Updates the permanent transfer record
        transferRecords[_destination][nextTransferId] = TransferRecord({
            amount: _usdValue,
            blockNumber: block.number
        });

        // Add to pending transfers
        pendingTransfers.push(
            PendingTransfer({amount: _usdValue, blockNumber: block.number})
        );

        pendingBridgeAmount += _usdValue;
        nextTransferId++;
        return
            _transferRemote(_destination, _recipient, _usdValue, _hookPayment);
    }

    function balanceOf(
        address _account
    ) external view override returns (uint256) {
        return _account.balance;
    }

    /**
     * @inheritdoc TokenRouter
     * @dev No-op because native amount is transferred in `msg.value`
     */
    function _transferFromSender(
        uint256
    ) internal pure override returns (bytes memory) {
        return bytes(""); // no metadata
    }

    /**
     * @dev Sends `_amount` of native token to `_recipient` balance.
     * @inheritdoc TokenRouter
     * @dev Receives the USD value of the incoming native token and converts it to the local native token.
     * @dev Takes the inbound bridging fee from the user and distributes to liquidity providers + Insurance Fund.
     */
    function _transferTo(
        address _recipient,
        uint256 _amount,
        bytes calldata
    ) internal virtual override nonReentrant {
        // Get the latest native token/USD price
        uint256 nativePrice = getLatestPrice();

        // Calculate the amount that was received in native token
        uint256 nativeValue = (_amount * 1e18) / nativePrice;

        // Take the inbound bridging fee
        uint256 fee = (nativeValue * INBOUND_FEE_PERCENTAGE) / 10000;
        uint256 amountAfterFee = nativeValue - fee;
        _distributeFees(fee);

        Address.sendValue(payable(_recipient), amountAfterFee);
    }

    /**
     * @dev Gets the latest native token/USD price from the appropriate price feed
     * @return price The latest native token/USD price
     */
    function getLatestPrice() public view returns (uint256) {
        if (isEthereum) {
            (, int256 answer, , , ) = chainlinkDataFeed.latestRoundData();
            require(answer > 0, "Invalid ETH/USD price");
            return uint256(answer);
        } else {
            IUmbrellaFeeds.PriceData memory priceData = umbrellaFeeds
                .getPriceDataByName("RBTC-USD");
            require(priceData.price > 0, "Invalid RBTC/USD price");
            return uint256(priceData.price);
        }
    }

    function getInsuranceFundAmount() public view returns (uint256) {
        // Determine the amount of native token in the Insurance Fund
        uint256 insuranceFundNativeAmount = address(insuranceFund).balance;

        // Get the latest native token/USD price
        uint256 nativePrice = getLatestPrice();

        // Determine the amount of USD value in the Insurance Fund
        uint256 insuranceFundUsdAmount = (insuranceFundNativeAmount *
            nativePrice) / 1e18;
        return insuranceFundUsdAmount;
    }

    /**
     * @dev Hyperspeed Bridge: Sends the current amount of funds in the Insurance Fund in the message.
     * @dev Hyperspeed Bridge: Sends the current amount of available liquidity in the message.
     * @dev Hyperspeed Bridge: Sends the transfer ID in the message.
     */
    function _transferRemote(
        uint32 _destination,
        bytes32 _recipient,
        uint256 _amountOrId,
        uint256 _value,
        bytes memory _hookMetadata,
        address _hook
    ) internal virtual override returns (bytes32 messageId) {
        uint256 nativePrice = getLatestPrice();
        uint256 _availableLiquidity = (totalLiquidity() * nativePrice) / 1e18;
        uint256 _insuranceFundAmount = getInsuranceFundAmount();

        bytes memory _tokenMetadata = abi.encode(
            _insuranceFundAmount,
            _availableLiquidity,
            nextTransferId,
            block.number
        );
        bytes memory _tokenMessage = TokenMessage.format(
            _recipient,
            _amountOrId,
            _tokenMetadata
        );

        messageId = _Router_dispatch(
            _destination,
            _value,
            _tokenMessage,
            _hookMetadata,
            _hook
        );

        emit SentTransferRemote(_destination, _recipient, _amountOrId);
    }

    /**
     * @dev Hyperspeed Bridge: Receives and stores the current amount of funds in the Insurance Fund on the outbound chain.
     */
    function _handle(
        uint32 _origin,
        bytes32,
        bytes calldata _message
    ) internal virtual override {
        bytes32 recipient = TokenMessage.recipient(_message);
        uint256 amount = TokenMessage.amount(_message);
        bytes calldata metadata = TokenMessage.metadata(_message);
        (
            uint256 _insuranceFundAmount,
            uint256 _availableLiquidity,
            uint256 _transferId,
            uint256 _blockNumber
        ) = abi.decode(metadata, (uint256, uint256, uint256, uint256));

        if (transferRecords[_origin][_transferId].amount != 0) {
            // Reorg detected
            reorgedTransfers[_origin].push(
                ReorgedTransfer({
                    amount: transferRecords[_origin][_transferId].amount,
                    blockNumber: transferRecords[_origin][_transferId]
                        .blockNumber,
                    originalIndex: _transferId
                })
            );

            // Pull funds from insurance fund
            uint256 reorgAmountUsd = transferRecords[_origin][_transferId]
                .amount;
            uint256 reorgAmountNative = (reorgAmountUsd * 1e18) /
                getLatestPrice();
            insuranceFund.liquidateForReorg(reorgAmountNative);
        }

        // Store the transfer record
        transferRecords[_origin][_transferId] = TransferRecord({
            amount: amount,
            blockNumber: _blockNumber
        });

        // Update the Insurance Fund and Available Liquidity that is on the other chain
        otherChainInsuranceFundAmount = _insuranceFundAmount;
        otherChainAvailableLiquidity = _availableLiquidity;

        // Transfer the bridged asset to the recipient
        _transferTo(address(uint160(uint256(recipient))), amount, metadata);
        emit ReceivedTransferRemote(_origin, recipient, amount);
    }

    function _processFinalizedTransfers() internal {
        uint256 i = 0;
        while (i < pendingTransfers.length) {
            if (
                pendingTransfers[i].blockNumber + FINALITY_PERIOD <=
                block.number
            ) {
                pendingBridgeAmount -= pendingTransfers[i].amount;

                // Remove the processed transfer from pendingTransfers
                pendingTransfers[i] = pendingTransfers[
                    pendingTransfers.length - 1
                ];
                pendingTransfers.pop();
            } else {
                i++;
            }
        }
    }

    function depositBridgeLiquidity() external payable {
        require(msg.value > 0, "Must deposit some liquidity");

        uint256 newShares;
        if (totalLiquidityShares == 0) {
            newShares = msg.value;
        } else {
            newShares =
                (msg.value * totalLiquidityShares) /
                (address(this).balance - msg.value - totalFees);
        }

        userLiquidityShares[msg.sender] += newShares;
        totalLiquidityShares += newShares;
        userFeeIndex[msg.sender] = feeIndex;

        emit LiquidityDeposited(msg.sender, msg.value, newShares);
    }

    function withdrawBridgeLiquidity(uint256 _shares) external nonReentrant {
        require(
            _shares > 0 && _shares <= userLiquidityShares[msg.sender],
            "Invalid share amount"
        );

        _claimFees(msg.sender);

        uint256 totalAssets = address(this).balance - totalFees;
        uint256 assetAmount = (_shares * totalAssets) / totalLiquidityShares;

        userLiquidityShares[msg.sender] -= _shares;
        totalLiquidityShares -= _shares;

        require(
            address(this).balance >= assetAmount,
            "Insufficient contract balance"
        );

        payable(msg.sender).transfer(assetAmount);
        emit LiquidityWithdrawn(msg.sender, assetAmount, _shares);
    }

    function claimFees() external {
        _claimFees(msg.sender);
    }

    function _claimFees(address _user) internal nonReentrant {
        uint256 feesClaimed = pendingFees(_user);
        if (feesClaimed > 0) {
            totalFees -= feesClaimed;
            userFeeIndex[_user] = feeIndex;
            payable(_user).transfer(feesClaimed);
        }
    }

    function _distributeFees(uint256 _fee) internal {
        // Determine fee split
        uint256 insuranceFundFee = (_fee * INSURANCE_FUND_REWARD_SHARE) / 100;
        uint256 liquidityProviderFee = (_fee *
            LIQUIDITY_PROVIDER_REWARD_SHARE) / 100;

        // Allocate liquidity provider fees
        totalFees += liquidityProviderFee;

        // Distribute to insurance fund
        (bool success, ) = address(insuranceFund).call{value: insuranceFundFee}(
            ""
        );
        require(success, "Insurance Fund fee transfer failed");

        if (totalLiquidityShares > 0) {
            feeIndex +=
                (liquidityProviderFee * PRECISION) /
                totalLiquidityShares;
        }
    }

    function pendingFees(address _user) public view returns (uint256) {
        return
            (userLiquidityShares[_user] * (feeIndex - userFeeIndex[_user])) /
            PRECISION;
    }

    function getUserLiquidity(address _user) public view returns (uint256) {
        uint256 totalAssets = address(this).balance - totalFees;
        return
            (userLiquidityShares[_user] * totalAssets) / totalLiquidityShares;
    }

    function totalLiquidity() public view returns (uint256) {
        return address(this).balance - totalFees;
    }

    receive() external payable {
        emit Donation(msg.sender, msg.value);
    }
}
