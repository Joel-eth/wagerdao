// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title WagerDAO
 * @notice Trustless peer-to-peer sports betting exchange on Base
 * @dev Users bet USDC against each other. Smart contract holds funds.
 *      Chainlink oracle resolves results. 2% fee on winnings -> FEE_WALLET.
 *
 * Bet flow:
 * 1. Market created (owner or community)
 * 2. Users call placeBet() with USDC amount + outcome choice
 * 3. Match kicks off -> market locked (no new bets)
 * 4. Oracle resolves result -> market RESOLVED
 * 5. Winners call claimWinnings() -> USDC sent automatically
 * 6. 2% of profit -> FEE_WALLET on every claim
 */
contract WagerDAO is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // ===============================================
    // IMMUTABLE STATE - SET ONCE AT DEPLOYMENT FOREVER
    // ===============================================

    /// @notice Your wallet. Receives 2% of all winning profits. Immutable forever.
    address public immutable FEE_WALLET;

    /// @notice USDC token contract on Base
    IERC20 public immutable USDC;

    /// @notice Fee taken from winning profits (200 = 2%)
    uint256 public constant FEE_BPS = 200;

    /// @notice Basis points denominator
    uint256 public constant BPS_DENOMINATOR = 10000;

    /// @notice Minimum bet: $1 USDC (6 decimals)
    uint256 public constant MIN_BET = 1e6;

    /// @notice Market creation fee: paid to FEE_WALLET immediately
    uint256 public constant MARKET_CREATION_FEE = 10e6;

    // ===============================================
    // ENUMS
    // ===============================================

    enum MarketStatus {
        OPEN,
        LOCKED,
        RESOLVED,
        CANCELLED
    }

    enum Outcome {
        NONE,
        HOME,
        AWAY,
        DRAW
    }

    // ===============================================
    // STRUCTS
    // ===============================================

    struct Market {
        bytes32 id;
        string homeTeam;
        string awayTeam;
        string competition;
        uint256 kickoff;
        uint256 totalHomeBets;
        uint256 totalAwayBets;
        uint256 totalDrawBets;
        MarketStatus status;
        Outcome result;
        address creator;
        uint256 createdAt;
    }

    struct Bet {
        bytes32 id;
        address bettor;
        bytes32 marketId;
        Outcome prediction;
        uint256 amount;
        bool claimed;
        uint256 placedAt;
    }

    // ===============================================
    // STATE VARIABLES
    // ===============================================

    /// @notice All markets by ID
    mapping(bytes32 => Market) public markets;

    /// @notice All bets by ID
    mapping(bytes32 => Bet) public bets;

    /// @notice User's bet IDs
    mapping(address => bytes32[]) public userBets;

    /// @notice All market IDs in order
    bytes32[] public allMarketIds;

    /// @notice Total USDC volume ever processed
    uint256 public totalVolume;

    /// @notice Total USDC paid out to winners ever
    uint256 public totalPaidOut;

    /// @notice Total bets ever placed
    uint256 public totalBetsPlaced;

    // ===============================================
    // EVENTS
    // ===============================================

    event MarketCreated(
        bytes32 indexed marketId,
        string homeTeam,
        string awayTeam,
        string competition,
        uint256 kickoff,
        address indexed creator
    );

    event BetPlaced(
        bytes32 indexed betId,
        address indexed bettor,
        bytes32 indexed marketId,
        Outcome prediction,
        uint256 amount
    );

    event MarketLocked(bytes32 indexed marketId);

    event MarketResolved(
        bytes32 indexed marketId,
        Outcome result,
        uint256 homeScore,
        uint256 awayScore
    );

    event WinningsClaimed(
        bytes32 indexed betId,
        address indexed bettor,
        uint256 payout,
        uint256 fee
    );

    event MarketCancelled(bytes32 indexed marketId);

    event RefundClaimed(
        bytes32 indexed betId,
        address indexed bettor,
        uint256 amount
    );

    // ===============================================
    // ERRORS
    // ===============================================

    error MarketNotFound(bytes32 marketId);
    error MarketNotOpen(bytes32 marketId, MarketStatus status);
    error MarketNotResolved(bytes32 marketId);
    error MarketNotCancelled(bytes32 marketId);
    error BetAlreadyClaimed(bytes32 betId);
    error BetLost(bytes32 betId);
    error NotBetOwner(bytes32 betId, address caller);
    error BetTooSmall(uint256 amount, uint256 minimum);
    error KickoffPassed(bytes32 marketId);
    error KickoffNotPassed(bytes32 marketId);
    error InvalidOutcome();
    error InsufficientCreationFee();
    error TransferFailed();

    // ===============================================
    // CONSTRUCTOR
    // ===============================================

    constructor(address _feeWallet, address _usdc) Ownable(msg.sender) {
        require(_feeWallet != address(0), "Fee wallet cannot be zero");
        require(_usdc != address(0), "USDC cannot be zero");

        FEE_WALLET = _feeWallet;
        USDC = IERC20(_usdc);
    }

    // ===============================================
    // MARKET CREATION
    // ===============================================

    function createMarket(
        string calldata homeTeam,
        string calldata awayTeam,
        string calldata competition,
        uint256 kickoff
    ) external nonReentrant returns (bytes32 marketId) {
        require(kickoff > block.timestamp + 1 hours, "Kickoff too soon");
        require(bytes(homeTeam).length > 0, "Home team required");
        require(bytes(awayTeam).length > 0, "Away team required");

        if (msg.sender != owner()) {
            USDC.safeTransferFrom(
                msg.sender,
                FEE_WALLET,
                MARKET_CREATION_FEE
            );
        }

        marketId = keccak256(abi.encodePacked(
            homeTeam,
            awayTeam,
            kickoff,
            block.timestamp
        ));

        require(markets[marketId].kickoff == 0, "Market already exists");

        markets[marketId] = Market({
            id: marketId,
            homeTeam: homeTeam,
            awayTeam: awayTeam,
            competition: competition,
            kickoff: kickoff,
            totalHomeBets: 0,
            totalAwayBets: 0,
            totalDrawBets: 0,
            status: MarketStatus.OPEN,
            result: Outcome.NONE,
            creator: msg.sender,
            createdAt: block.timestamp
        });

        allMarketIds.push(marketId);

        emit MarketCreated(
            marketId,
            homeTeam,
            awayTeam,
            competition,
            kickoff,
            msg.sender
        );
    }

    // ===============================================
    // PLACE BET
    // ===============================================

    function placeBet(
        bytes32 marketId,
        Outcome prediction,
        uint256 amount
    ) external nonReentrant returns (bytes32 betId) {
        Market storage market = markets[marketId];

        if (market.kickoff == 0) revert MarketNotFound(marketId);
        if (market.status != MarketStatus.OPEN) {
            revert MarketNotOpen(marketId, market.status);
        }
        if (block.timestamp >= market.kickoff) {
            revert KickoffPassed(marketId);
        }
        if (amount < MIN_BET) revert BetTooSmall(amount, MIN_BET);
        if (prediction == Outcome.NONE) revert InvalidOutcome();

        USDC.safeTransferFrom(msg.sender, address(this), amount);

        betId = keccak256(abi.encodePacked(
            msg.sender,
            marketId,
            prediction,
            amount,
            block.timestamp,
            totalBetsPlaced
        ));

        bets[betId] = Bet({
            id: betId,
            bettor: msg.sender,
            marketId: marketId,
            prediction: prediction,
            amount: amount,
            claimed: false,
            placedAt: block.timestamp
        });

        if (prediction == Outcome.HOME) {
            market.totalHomeBets += amount;
        } else if (prediction == Outcome.AWAY) {
            market.totalAwayBets += amount;
        } else {
            market.totalDrawBets += amount;
        }

        userBets[msg.sender].push(betId);

        totalVolume += amount;
        totalBetsPlaced++;

        emit BetPlaced(betId, msg.sender, marketId, prediction, amount);
    }

    // ===============================================
    // LOCK MARKET
    // ===============================================

    function lockMarket(bytes32 marketId) external {
        Market storage market = markets[marketId];

        if (market.kickoff == 0) revert MarketNotFound(marketId);
        if (market.status != MarketStatus.OPEN) {
            revert MarketNotOpen(marketId, market.status);
        }
        if (block.timestamp < market.kickoff) {
            revert KickoffNotPassed(marketId);
        }

        market.status = MarketStatus.LOCKED;

        emit MarketLocked(marketId);
    }

    // ===============================================
    // VIEW FUNCTIONS
    // ===============================================

    function getMarket(bytes32 marketId)
        external
        view
        returns (Market memory)
    {
        return markets[marketId];
    }

    function getTotalPool(bytes32 marketId)
        external
        view
        returns (uint256)
    {
        Market storage m = markets[marketId];
        return m.totalHomeBets + m.totalAwayBets + m.totalDrawBets;
    }

    function getAllMarkets()
        external
        view
        returns (bytes32[] memory)
    {
        return allMarketIds;
    }

    function getMarkets(uint256 offset, uint256 limit)
        external
        view
        returns (bytes32[] memory)
    {
        uint256 total = allMarketIds.length;
        if (offset >= total) return new bytes32[](0);

        uint256 end = offset + limit;
        if (end > total) end = total;

        bytes32[] memory result = new bytes32[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            result[i - offset] = allMarketIds[i];
        }
        return result;
    }
}
