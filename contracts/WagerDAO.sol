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

    // Logic functions implemented Day 2-4
}
