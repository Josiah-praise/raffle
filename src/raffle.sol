//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "./interfaces/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";


contract Raffle is Ownable {
    uint256 public constant LEAST_DURATION = 1 hours;
    Config public raffleConfig;
    IERC20 public payoutToken;

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
        TokenType entryFeeType;
        uint256 entryFee;
        uint256 minimumDonation;
        Type raffleType;
        address erc20EntryFeeTokenAddress;
        address erc20PayoutTokenAddress;
    }

    event RaffleInitialized(address indexed admin, uint256 id);
    event ConfigInfo(
        uint256 duration,
        LifeCycle state,
        TokenType payoutType,
        TokenType entryFeeType,
        uint256 entryFee,
        uint256 minimumDonation,
        Type raffleType,
        address erc20EntryFeeTokenAddress,
        address erc20PayoutTokenAddress
    );
    event RaffleFunded(uint256 amount);

    error InvalidDuration(uint256 _duration);
    error ZeroAddressError();
    error InvalidConfig();
    error PayoutTokenAddressNotSet();
    error EntryFeeTokenAddressNotSet();
    error PrizePoolEmptyError();
    error InsufficientAllowanceError();

    constructor(
        uint256 _duration,
        TokenType _payoutType,
        TokenType _entryFeeType,
        uint256 _entryFee,
        uint256 _minimumDonation,
        Type _raffleType,
        uint256 nextRaffleId,
        address _admin
    ) Ownable(_admin) {
        raffleConfig = createConfig(_duration, _payoutType, _entryFeeType, _entryFee, _minimumDonation, _raffleType);

        emit RaffleInitialized(_admin, nextRaffleId);
    }

    ///@notice create a config struct for a newly created raffle
    function createConfig(
        uint256 _duration,
        TokenType _payoutType,
        TokenType _entryFeeType,
        uint256 _entryFee,
        uint256 _minimumDonation,
        Type _raffleType
    ) internal returns (Config memory) {
        // a raffle must last for at least 2 days
        if (_duration < LEAST_DURATION) {
            revert InvalidDuration(_duration);
        }

        Config memory newConfig = Config({
            duration: _duration,
            state: LifeCycle.INACTIVE,
            payoutType: _payoutType,
            entryFeeType: _entryFeeType,
            entryFee: _entryFee,
            minimumDonation: _minimumDonation,
            raffleType: _raffleType,
            erc20EntryFeeTokenAddress: address(0),
            erc20PayoutTokenAddress: address(0)
        });

        emit ConfigInfo(
            _duration,
            LifeCycle.INACTIVE,
            _payoutType,
            _entryFeeType,
            _entryFee,
            _minimumDonation,
            _raffleType,
            address(0),
            address(0)
        );

        return newConfig;
    }

    ///@notice allows an admin to set the address of the token that is used to pay
    /// entry fee for the raffle
    ///@dev this needs to be called if the entry fee asset is an ERC20
    function setErc20EntryFeeTokenAddress(address erc20Address) public onlyOwner{
        if (raffleConfig.entryFeeType != TokenType.ERC20) {
            revert InvalidConfig();
        }

        if (address(0) == erc20Address) {
            revert ZeroAddressError();
        }

        // prevents an admin from changing the address once they've set it
        if (raffleConfig.erc20EntryFeeTokenAddress != address(0)) {
            revert InvalidConfig();
        }

        raffleConfig.erc20EntryFeeTokenAddress = erc20Address;
        emit ConfigInfo(
            raffleConfig.duration,
            raffleConfig.state,
            raffleConfig.payoutType,
            raffleConfig.entryFeeType,
            raffleConfig.entryFee,
            raffleConfig.minimumDonation,
            raffleConfig.raffleType,
            raffleConfig.erc20EntryFeeTokenAddress,
            raffleConfig.erc20PayoutTokenAddress
        );
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

        emit ConfigInfo(
            raffleConfig.duration,
            raffleConfig.state,
            raffleConfig.payoutType,
            raffleConfig.entryFeeType,
            raffleConfig.entryFee,
            raffleConfig.minimumDonation,
            raffleConfig.raffleType,
            raffleConfig.erc20EntryFeeTokenAddress,
            raffleConfig.erc20PayoutTokenAddress
        );
    }

    ///@notice changes a raffles state from INACTIVE to ACTIVE
    ///@dev an admin can call this anytime to activate a raffle and it only fails if the prizePool is empty (0)
    function activateRaffle() public onlyOwner{
        if (_prizePool == 0) revert PrizePoolEmptyError();
        raffleConfig.state = LifeCycle.ACTIVE;
    }

    ///@notice reward the winner with the selected token
    function rewardWithErc20(uint256 amount, address payable winner, address erc20Address)
        internal
        pure
        returns (bool)
    {
        // send the amount to the winner.
    }

    ///@notice allows an admin to fund a raffle with ERC20 tokens
    function fundRaffleWithErc20(uint256 amount, address from) public onlyOwner returns (bool) {
        if (raffleConfig.payoutType != TokenType.ERC20) return false;

        // ensure that if the entry fee asset is of type ERC20 token
        if (!_validateErc20EntryFeeTokenAddress()) {
            revert EntryFeeTokenAddressNotSet();
        }

        // ensure that if the payout asset is of type ERC20 token
        if (!_validateErc20PayoutTokenAddress()) {
            revert PayoutTokenAddressNotSet();
        }

        _prizePool += amount;

        bool success = payoutToken.transferFrom(from, address(this), amount);

        if (!success) revert InsufficientAllowanceError();

        emit RaffleFunded(amount);
        return success;
    }

    function fundRaffleWithEth() public payable onlyOwner returns (bool) {
        if (raffleConfig.payoutType != TokenType.ETH) return false;

        _prizePool += msg.value;

        emit RaffleFunded(msg.value);
        return true;
    }

    ///@notice checks that when entry fee asset is ERC20, an ERC20 address other than address 0 is set
    function _validateErc20EntryFeeTokenAddress() private view returns (bool) {
        return raffleConfig.erc20EntryFeeTokenAddress != address(0);
    }

    ///@notice checks that when payout Token type is ERC20, an ERC20 address other than address 0 is set
    function _validateErc20PayoutTokenAddress() private view returns (bool) {
        return raffleConfig.erc20PayoutTokenAddress != address(0);
    }
}
