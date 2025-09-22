//SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "./interfaces/IERC20.sol";

// TODO use openZeppelin's ownable contract and then protect setERC20 functions with onlyOwner

contract Raffle {
    address public immutable admin;
    uint256 public constant LEAST_DURATION = 1 hours;
    Config public raffleConfig;
    IERC20 public payoutToken;

    uint256 private _totalEntryFee; // an accumulation of the fees payed to enter the raffle
    uint256 private _prizePool; // an accumulation of funding(from the admin)  and donations

    RaffleParticipant[] public raffleParticipants; // addresses that paid the raffle fee to enter the raffle
    mapping(address=>uint256) public donations; // tracks total donations per donor
    mapping(address=>uint256) public entries; // tracks number of entries per raffle participant particularly needed for weighted raffles

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
        address ERC20EntryFeeTokenAddress;
        address ERC20PayoutTokenAddress;
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
        address ERC20EntryFeeTokenAddress,
        address ERC20PayoutTokenAddress
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
    ) {
        raffleConfig = createConfig(_duration, _payoutType, _entryFeeType, _entryFee, _minimumDonation, _raffleType);

        admin = _admin;
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
            ERC20EntryFeeTokenAddress: address(0),
            ERC20PayoutTokenAddress: address(0)
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

    // TODO onlyadmin
    ///@notice allows an admin to set the address of the token that is used to pay
    /// entry fee for the raffle
    ///@dev this needs to be called if the entry fee asset is an ERC20
    function setERC20EntryFeeTokenAddress(address ERC20Address) public {
        if (raffleConfig.entryFeeType != TokenType.ERC20) {
            revert InvalidConfig();
        }

        if (address(0) == ERC20Address) {
            revert ZeroAddressError();
        }

        // prevents an admin from changing the address once they've set it
        if (raffleConfig.ERC20EntryFeeTokenAddress != address(0)) {
            revert InvalidConfig();
        }

        raffleConfig.ERC20EntryFeeTokenAddress = ERC20Address;
        emit ConfigInfo(
            raffleConfig.duration,
            raffleConfig.state,
            raffleConfig.payoutType,
            raffleConfig.entryFeeType,
            raffleConfig.entryFee,
            raffleConfig.minimumDonation,
            raffleConfig.raffleType,
            raffleConfig.ERC20EntryFeeTokenAddress,
            raffleConfig.ERC20PayoutTokenAddress
        );
    }

    // TODO onlyadmin
    ///@notice allows an admin to set the address of the token that is used to pay
    /// that is payed out to the winner
    ///@dev this needs to be called if the payout asset is an ERC20
    function setERC20PayoutTokenAddress(address ERC20Address) public {
        if (raffleConfig.payoutType != TokenType.ERC20) {
            revert InvalidConfig();
        }

        if (address(0) == ERC20Address) {
            revert ZeroAddressError();
        }

        // prevents an admin from changing the address once they've set it
        if (raffleConfig.ERC20PayoutTokenAddress != address(0)) {
            revert InvalidConfig();
        }

        raffleConfig.ERC20PayoutTokenAddress = ERC20Address;
        payoutToken = IERC20(ERC20Address);

        emit ConfigInfo(
            raffleConfig.duration,
            raffleConfig.state,
            raffleConfig.payoutType,
            raffleConfig.entryFeeType,
            raffleConfig.entryFee,
            raffleConfig.minimumDonation,
            raffleConfig.raffleType,
            raffleConfig.ERC20EntryFeeTokenAddress,
            raffleConfig.ERC20PayoutTokenAddress
        );
    }


    // TODO onlyadmin
    ///@notice changes a raffles state from INACTIVE to ACTIVE
    ///@dev an admin can call this anytime to activate a raffle and it only fails if the prizePool is empty (0)
    function activateRaffle() public {
        if (_prizePool == 0) revert PrizePoolEmptyError();
        raffleConfig.state = LifeCycle.ACTIVE;
    }

    ///@notice reward the winner with the selected token
    function rewardWithERC20(uint256 amount, address payable winner, address ERC20Address)
        internal
        pure
        returns (bool)
    {
        // send the amount to the winner.
    }

    // TODO onlyadmin
    ///@notice allows an admin to fund a raffle with ERC20 tokens
    function fundRaffleWithERC20(uint256 amount, address from) public returns(bool){
        if (raffleConfig.payoutType != TokenType.ERC20) return false;

        // ensure that if the entry fee asset is of type ERC20 token
        if (!_validateERC20EntryFeeTokenAddress()) {
            revert EntryFeeTokenAddressNotSet();
        }

        // ensure that if the payout asset is of type ERC20 token
        if (!_validateERC20PayoutTokenAddress()) {
            revert PayoutTokenAddressNotSet();
        }

        _prizePool += amount;

        bool success = payoutToken.transferFrom(from, address(this), amount);

        if (!success) revert InsufficientAllowanceError();

        emit RaffleFunded(amount);
        return success;
    }

    // TODO onlyadmin
    function fundRaffleWithEth()public payable returns(bool) {
        if (raffleConfig.payoutType != TokenType.ETH) return false;

        _prizePool += msg.value;

        emit RaffleFunded(msg.value);
        return true;
    }

    ///@notice checks that when entry fee asset is ERC20, an ERC20 address other than address 0 is set
    function _validateERC20EntryFeeTokenAddress() private view returns (bool) {
        return raffleConfig.ERC20EntryFeeTokenAddress != address(0);
    }

    ///@notice checks that when payout Token type is ERC20, an ERC20 address other than address 0 is set
    function _validateERC20PayoutTokenAddress() private view returns (bool) {
        return raffleConfig.ERC20PayoutTokenAddress != address(0);
    }
}
