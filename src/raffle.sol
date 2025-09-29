//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "./interfaces/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Raffle is Ownable, ReentrancyGuard {
    uint256 public constant LEAST_DURATION = 1 hours;
    address public immutable RAFFLE_FACTORY;
    Config public raffleConfig;
    IERC20 public payoutToken;
    uint256 public startTime;

    uint256 private _totalEntryFee; // an accumulation of the fees payed to enter the raffle
    uint256 private _prizePool; // an accumulation of funding(from the admin)  and donations

    RaffleParticipant[] public raffleParticipants; // addresses that paid the raffle fee to enter the raffle
    mapping(address => uint256) public donations; // tracks total donations per donor
    mapping(address => uint256) public entries; // tracks number of entries per raffle participant particularly needed for weighted raffles

    enum LifeCycle {
        INACTIVE,
        ACTIVE,
        READY_FOR_PAYOUT,
        READY_FOR_DRAINAGE,
        COMPLETE
    }

    enum TokenType {
        ERC20,
        ETH
    }

    enum Type {
        WEIGHTED,
        BALANCED
    }

    // this allows weighted raffle participation
    struct RaffleParticipant {
        address participant;
    }
    // the config for a raffle

    struct Config {
        uint256 duration;
        LifeCycle state;
        TokenType payoutType;
        uint256 entryFee;
        uint256 minimumDonation;
        Type raffleType;
        address erc20PayoutTokenAddress;
        uint256 protocolPercentage;
    }

    event RaffleInitialized(address indexed admin, uint256 id);
    event ConfigInfo(
        uint256 duration,
        LifeCycle state,
        TokenType payoutType,
        uint256 entryFee,
        uint256 minimumDonation,
        Type raffleType,
        address erc20PayoutTokenAddress,
        uint256 protocolPercentage
    );
    event RaffleFunded(uint256 amount);

    error InvalidDuration(uint256 _duration);
    error ZeroAddressError();
    error InvalidConfig();
    error PayoutTokenAddressNotSet();
    error EntryFeeTokenAddressNotSet();
    error PrizePoolBalanceError();
    error InsufficientAllowanceError();
    error PayoutError();

    constructor(
        uint256 _duration,
        TokenType _payoutType,
        uint256 _entryFee,
        uint256 _minimumDonation,
        Type _raffleType,
        uint256 nextRaffleId,
        address _raffleAdmin,
        address _raffleFactory,
        uint256 _protocolPercentage
    ) Ownable(_raffleAdmin) {
        raffleConfig = _createConfig(
            _duration, _payoutType, _entryFee, _minimumDonation, _raffleType, _protocolPercentage
        );

        RAFFLE_FACTORY = _raffleFactory;

        emit RaffleInitialized(_raffleAdmin, nextRaffleId);
    }

    ///@notice create a config struct for a newly created raffle
    function _createConfig(
        uint256 _duration,
        TokenType _payoutType,
        uint256 _entryFee,
        uint256 _minimumDonation,
        Type _raffleType,
        uint256 _protocolPercentage
    ) private returns (Config memory) {
        // a raffle must last for at least 2 days
        if (_duration < LEAST_DURATION) {
            revert InvalidDuration(_duration);
        }

        Config memory newConfig = Config({
            duration: _duration,
            state: LifeCycle.INACTIVE,
            payoutType: _payoutType,
            entryFee: _entryFee,
            minimumDonation: _minimumDonation,
            raffleType: _raffleType,
            erc20PayoutTokenAddress: address(0),
            protocolPercentage: _protocolPercentage
        });

        emit ConfigInfo(
            _duration,
            LifeCycle.INACTIVE,
            _payoutType,
            _entryFee,
            _minimumDonation,
            _raffleType,
            address(0),
            _protocolPercentage
        );

        return newConfig;
    }

    ///@notice allows an admin to set the address of the token that is used to pay
    /// that is payed out to the winner
    ///@dev this needs to be called if the payout asset is an ERC20
    function setErc20PayoutTokenAddress(address erc20Address) public onlyOwner {
        if (raffleConfig.payoutType != TokenType.ERC20) {
            revert InvalidConfig();
        }

        if (address(0) == erc20Address) {
            revert ZeroAddressError();
        }

        // prevents an admin from changing the address once they've set it
        if (raffleConfig.erc20PayoutTokenAddress != address(0)) {
            revert InvalidConfig();
        }

        raffleConfig.erc20PayoutTokenAddress = erc20Address;
        payoutToken = IERC20(erc20Address);

        _emitConfig();
    }

    ///@notice changes a raffles state from INACTIVE to ACTIVE
    ///@dev an admin can call this anytime to activate a raffle and it only fails if the prizePool is empty (0)
    function activateRaffle() public onlyOwner {
        if (_prizePool == 0) revert PrizePoolBalanceError();
        raffleConfig.state = LifeCycle.ACTIVE;

        startTime = block.timestamp;
        _emitConfig();
    }

    ///@notice reward the winner with the selected token
    function _rewardWinnerWithErc20(address winner) internal returns (bool) {
        if (_prizePool == 0 || _prizePool != payoutToken.balanceOf(address(this))) revert PrizePoolBalanceError();
        uint256 protocolFee = (_prizePool * raffleConfig.protocolPercentage) / 10000;
        uint256 winnerReward = _prizePool - protocolFee;

        // pay protocol fee
        _prizePool -= protocolFee;
        bool protocolFeeSent = payoutToken.transferFrom(address(this), RAFFLE_FACTORY, protocolFee);

        if (!protocolFeeSent) revert PayoutError();

        // send to winner
        _prizePool -= winnerReward;
        bool rewardSent = payoutToken.transferFrom(address(this), winner, winnerReward);

        if (!rewardSent) revert PayoutError();
        return true;
    }

    ///@notice reward the winner with the selected token
    function _rewardWinnerWithEth(address payable winner) internal nonReentrant returns (bool) {
        if (_prizePool == 0 || _prizePool != address(this).balance) revert PrizePoolBalanceError();
        uint256 protocolFee = (_prizePool * raffleConfig.protocolPercentage) / 10000;
        uint256 winnerReward = _prizePool - protocolFee;

        // pay protocol fee
        _prizePool -= protocolFee;
        (bool protocolFeeSent,) = RAFFLE_FACTORY.call{value: protocolFee}("");

        if (!protocolFeeSent) revert PayoutError();

        // send to winner
        _prizePool -= winnerReward;
        (bool rewardSent,) = winner.call{value: winnerReward}("");

        if (!rewardSent) revert PayoutError();
        return true;
    }

    ///@notice allows an admin to fund a raffle with ERC20 tokens
    function fundRaffleWithErc20(uint256 amount, address from) public onlyOwner returns (bool) {
        if (raffleConfig.payoutType != TokenType.ERC20) return false;

        if (_validateErc20PayoutTokenAddress() == false) revert PayoutTokenAddressNotSet();

        _prizePool += amount;

        bool success = payoutToken.transferFrom(from, address(this), amount);

        if (!success) revert InsufficientAllowanceError();

        emit RaffleFunded(amount);
        return success;
    }

    ///@notice allows an admin to fund a raffle with ETH
    function fundRaffleWithEth() public payable onlyOwner returns (bool) {
        if (raffleConfig.payoutType != TokenType.ETH) return false;

        _prizePool += msg.value;

        emit RaffleFunded(msg.value);
        return true;
    }

    ///@notice checks that when payout Token type is ERC20, an ERC20 address other than address 0 is set
    function _validateErc20PayoutTokenAddress() private view returns (bool) {
        return raffleConfig.erc20PayoutTokenAddress != address(0);
    }

    ///@notice helper function to emit Config info
    function _emitConfig() private {
        emit ConfigInfo(
            raffleConfig.duration,
            raffleConfig.state,
            raffleConfig.payoutType,
            raffleConfig.entryFee,
            raffleConfig.minimumDonation,
            raffleConfig.raffleType,
            raffleConfig.erc20PayoutTokenAddress,
            raffleConfig.protocolPercentage
        );
    }
}
