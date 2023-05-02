// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

//import 'https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/cryptography/ECDSA.sol';
import "./IWETH.sol";

contract SP_Bet is
    Initializable,
    PausableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    IERC20 public token;
    mapping(uint256 => Bet) public bets;
    uint256 _betcount;
    address zero;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract with the given ERC20 token contract
     * @param _tokenContract Address of the ERC20 token contract to be used
     */
    function initialize(IERC20 _tokenContract) public initializer {
        __Pausable_init();
        __Ownable_init();
        __UUPSUpgradeable_init();
        token = _tokenContract;
        _betcount = 0;
        zero = address(0x0);
    }

    /**
     * @notice Pause the contract
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the contract
     */
    function unpause() public onlyOwner {
        _unpause();
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    event BetCreated(
        uint256 betId,
        uint256 amount,
        address maker,
        address taker,
        uint256 endTs,
        string title,
        string content,
        uint256 consensusFee
    );
    event BetTaken(uint256 betId, address taker, BetStatus status);
    event BetDecided(uint256 betId, Winner winner, Result result);
    event BetVoted(uint256 betId, BetStatus status, Result result);
    event BetRevealed(uint256 betId, BetStatus status, Result result);
    event BetPaid(uint256 betId);
    event BetWithdrawn(uint256 betId);

    enum BetStatus {
        Initial,
        Active,
        Finished,
        Revealed,
        Decided,
        Paid,
        Withdrawn
    }
    enum Winner {
        Maker,
        Taker,
        Void
    }

    struct Bet {
        uint256 betId;
        uint256 endTs;
        uint256 amount;
        uint256 consensusFee;
        address maker;
        address taker;
        string title;
        string content;
        BetStatus status;
        Result result;
    }

    struct Result {
        uint8 maker;
        bytes32 makerVoteHash;
        bytes32 makerVoteProof;
        bytes32 makerVoteStore;
        bool makerVoted;
        bool makerRevealed;
        uint8 taker;
        bytes32 takerVoteHash;
        bytes32 takerVoteProof;
        bytes32 takerVoteStore;
        bool takerVoted;
        bool takerRevealed;
    }

    function _betExists(uint betId) internal view returns (bool) {
        return (bets[betId].taker == zero) && (bets[betId].maker == zero);
    }

    function _toBytes(uint256 x) internal pure returns (bytes memory b) {
        b = new bytes(32);
        assembly {
            mstore(add(b, 32), x)
        }
    }

    /**
     * @notice Creates a new bet
     * @param amount The amount of tokens to bet
     * @param taker The address of the taker
     * @param endTs The end timestamp for the bet
     * @param title The title of the bet
     * @param content The content of the bet
     * @param consensusFee The consensus fee for the bet
     * @return betId The ID of the created bet
     */
    function createBet(
        uint amount,
        address taker,
        uint endTs,
        string calldata title,
        string calldata content,
        uint256 consensusFee
    ) external payable returns (uint betId) {
        address maker = msg.sender;
        uint makerBalance = token.balanceOf(maker);

        require(
            token.allowance(maker, address(this)) >= amount,
            "Not allowed to spend SP"
        );
        require(amount > 0, "Nothing to bet on");
        require(makerBalance >= amount, "Not enough funds to bet");
        require(
            endTs > block.timestamp,
            "Cannot create bet that resolves in the past"
        );

        Result memory result;
        bets[_betcount] = Bet(
            _betcount,
            endTs,
            amount,
            consensusFee,
            maker,
            taker,
            title,
            content,
            BetStatus.Initial,
            result
        );
        emit BetCreated(
            _betcount,
            amount,
            maker,
            taker,
            endTs,
            title,
            content,
            consensusFee
        );

        _betcount += 1;
        //token.transferFrom(maker, address(this), amount);

        return _betcount;
    }

    /**
     * @notice Take an existing bet
     * @param betId The ID of the bet to take
     */
    function takeBet(uint betId) external payable {
        address taker = msg.sender;
        address maker = bets[betId].maker;

        uint balance = token.balanceOf(taker);

        require(
            (bets[betId].taker == zero || bets[betId].taker == taker),
            "Cannot take this bet"
        );
        require(bets[betId].status == BetStatus.Initial, "Bet does not exist");
        require(taker != bets[betId].maker, "Cannot take your own bets");
        require(balance >= bets[betId].amount, "Not enough tokens to bet");
        require(
            token.allowance(taker, address(this)) >= bets[betId].amount,
            "Not allowed to spend SP"
        );

        bets[betId].status = BetStatus.Active;
        bets[betId].taker = taker;

        token.transferFrom(taker, address(this), bets[betId].amount);
        token.transferFrom(maker, address(this), bets[betId].amount);

        emit BetTaken(betId, taker, BetStatus.Active);
    }

    /**
     * @notice Get information about a bet
     * @param betId The ID of the bet
     * @return Id The bet ID
     * @return endTs The end timestamp of the bet
     * @return amount The amount of tokens in the bet
     * @return maker The address of the maker
     * @return taker The address of the taker
     * @return title The title of the bet
     * @return content The content of the bet
     * @return status The status of the bet
     * @return result The result of the bet
     */
    function getBet(
        uint betId
    )
        external
        view
        returns (
            uint Id,
            uint256 endTs,
            uint256 amount,
            address maker,
            address taker,
            string memory title,
            string memory content,
            BetStatus status,
            Result memory result
        )
    {
        Bet memory bet = bets[betId];
        return (
            bet.betId,
            bet.endTs,
            bet.amount,
            bet.maker,
            bet.taker,
            bet.title,
            bet.content,
            bet.status,
            bet.result
        );
    }

    /**
     * @notice Withdraw a bet that has not been taken
     * @param betId The ID of the bet to withdraw
     */
    function withdrawBet(uint betId) external {
        require(msg.sender == bets[betId].maker);
        require(bets[betId].status == BetStatus.Initial);
        bets[betId].status = BetStatus.Withdrawn;

        emit BetWithdrawn(betId);
    }

    /**
     * @notice Get the total count of bets
     * @return betCount The total count of bets
     */
    function getBetCount() external view returns (uint betCount) {
        return _betcount;
    }

    /**
     * @notice Vote on a bet's outcome
     * @param betId The ID of the bet
     * @param voteHash The hash of the vote
     * @param voteStore The storage for the vote
     */
    function voteBet(uint betId, bytes32 voteHash, bytes32 voteStore) external {
        Bet memory bet = bets[betId];
        // require(block.timestamp > bet.endTs, "Too early to vote");

        require(bet.status == BetStatus.Active, "Bet not available for voting");
        require(
            msg.sender == bet.maker || msg.sender == bet.taker,
            "Who are you btw?"
        );

        if (msg.sender == bet.maker) {
            require(!bet.result.makerVoted, "Maker already voted");

            bets[betId].result.makerVoteHash = voteHash;
            bets[betId].result.makerVoteStore = voteStore;
            bets[betId].result.makerVoted = true;
        } else if (msg.sender == bet.taker) {
            require(!bet.result.takerVoted, "Taker already voted");

            bets[betId].result.takerVoteHash = voteHash;
            bets[betId].result.takerVoteStore = voteStore;
            bets[betId].result.takerVoted = true;
        }

        if (bets[betId].result.makerVoted && bets[betId].result.takerVoted) {
            bets[betId].status = BetStatus.Finished;
            //decide(betId);
        }
        emit BetVoted(bet.betId, bets[betId].status, bets[betId].result);
    }

    /**
     * @notice Reveal a vote for a bet
     * @param betId The ID of the bet
     * @param vote The vote (0 or 1)
     * @param voteProof The salt used to generate the vote hash
     */
    function reveal(uint betId, uint8 vote, bytes32 voteProof) external {
        Bet memory bet = bets[betId];

        require(bet.status == BetStatus.Finished, "Not suitable for reveal");
        require(
            msg.sender == bet.maker || msg.sender == bet.taker,
            "Who are you btw?"
        );

        if (msg.sender == bet.maker) {
            require(!bet.result.makerRevealed, "Maker already revealed");
            require(
                getSaltedHash(vote, voteProof) == bet.result.makerVoteHash,
                "Vote Reveal: Revealed hash does not match commit"
            );
            bets[betId].result.maker = vote;
            bets[betId].result.makerVoteProof = voteProof;
            bets[betId].result.makerRevealed = true;
        } else if (msg.sender == bet.taker) {
            require(!bet.result.takerRevealed, "Taker already revealed");
            require(
                getSaltedHash(vote, voteProof) == bet.result.takerVoteHash,
                "Vote Reveal: Revealed hash does not match commit"
            );
            bets[betId].result.taker = vote;
            bets[betId].result.takerVoteProof = voteProof;
            bets[betId].result.takerRevealed = true;
        }

        if (
            bets[betId].result.makerRevealed && bets[betId].result.takerRevealed
        ) {
            bets[betId].status = BetStatus.Revealed;
            decide(betId);
        }

        emit BetRevealed(betId, bets[betId].status, bets[betId].result);
    }

    /**
     * @notice Decide the outcome of a bet based on the votes
     * @param betId The ID of the bet
     * @return outcome The outcome of the bet (0 or 1)
     */
    function decide(uint betId) internal {
        Bet memory bet = bets[betId];
        Winner winner;

        require(bet.status == BetStatus.Revealed, "Not suitable for decision");

        uint8 bidInt = bet.result.maker;
        uint8 takeInt = bet.result.taker;

        if ((bidInt + takeInt) == 0) {
            // Both voted 0, maker wins
            winner = Winner.Maker;
        } else if ((bidInt + takeInt) == 2) {
            // Both voted 1, taker wins
            winner = Winner.Taker;
        } else {
            // Voted differently, zero return
            winner = Winner.Void;
        }
        emit BetDecided(betId, winner, bet.result);
        bets[betId].status = BetStatus.Decided;

        payout(winner, betId);
    }

    /**
     * @notice Distribute the winnings to the winner and loser of the bet based on the bet outcome
     * @dev This function should only be called internally after the bet has been decided
     * @param winner The winner of the bet (Maker, Taker or Void)
     * @param betId The ID of the bet
     */
    function payout(Winner winner, uint256 betId) internal {
        Bet memory bet = bets[betId];
        require(bet.status == BetStatus.Decided, "Not ready to pay");
        (uint256 winnerPayout, uint256 loserPayout) = calcPayouts(
            bet.amount,
            bet.consensusFee
        );

        if (winner == Winner.Maker) {
            token.transfer(bet.maker, winnerPayout);
            token.transfer(bet.taker, loserPayout);
        } else if (winner == Winner.Taker) {
            token.transfer(bet.taker, winnerPayout);
            token.transfer(bet.maker, loserPayout);
        }

        bets[betId].status = BetStatus.Paid;
        emit BetPaid(betId);
    }

    /**
     * @notice Calculate the payouts for the winner and loser
     * @param amount The amount of tokens in the bet
     * @param consensusFee The consensus fee for the bet
     * @return winnerPayout The payout for the winner
     * @return loserPayout The payout for the loser
     */
    function calcPayouts(
        uint256 amount,
        uint256 consensusFee
    ) public pure returns (uint256, uint256) {
        uint256 totalAmount = amount * 2;
        uint256 loserPayout = (totalAmount / 100) * (consensusFee);
        uint256 winnerPayout = totalAmount - loserPayout;

        require(
            (winnerPayout + loserPayout) <= totalAmount,
            "Cannot print moneys"
        );

        return (winnerPayout, loserPayout);
    }

    /**
     * @notice Calculate the salted hash of the provided vote and salt
     * @param vote The participant's vote (0 or 1)
     * @param salt A random value used to obscure the participant's vote
     * @return The salted hash of the vote and salt
     */
    function getSaltedHash(
        uint8 vote,
        bytes32 salt
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(vote, salt));
    }
}
