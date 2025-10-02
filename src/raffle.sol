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

    address payable[] public raffleParticipants; // addresses that paid the raffle fee to enter the raffle
    mapping(address => uint256) public donations; // tracks total donations per donor
    uint256 public totalEntries;
    uint256 public totalFunds; // total funding from raffle owner
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
    event RaffleEntry(address indexed player, uint256 entryFee, TokenType tokenType);
    event RaffleDonation(address indexed donor, uint256 amount);

    error InvalidDuration(uint256 _duration);
    error ZeroAddressError();
    error InvalidConfig();
    error PayoutTokenAddressNotSet();
    error PrizePoolBalanceError();
    error InsufficientAllowanceError();
    error PayoutError();
    error RaffleReentryError();
    error RaffleNotActiveError();
    error RaffleEntryFeeError();
    error DonationError();
    error MinimumDonationError();
    error PayoutTypeError();
    error InvalidDonationRefundError();

    modifier isActive() {
        _updateLifeCycle();
        if (raffleConfig.state != LifeCycle.ACTIVE) revert RaffleNotActiveError();
        _;
    }

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
        raffleConfig =
            _createConfig(_duration, _payoutType, _entryFee, _minimumDonation, _raffleType, _protocolPercentage);

        RAFFLE_FACTORY = _raffleFactory;

        emit RaffleInitialized(_raffleAdmin, nextRaffleId);
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
        // raffle can only be activated when in an inactive state
        if (raffleConfig.state != LifeCycle.INACTIVE) return;
        // raffle cannot be activated with an empty prize pool
        if (_prizePool == 0) revert PrizePoolBalanceError();

        raffleConfig.state = LifeCycle.ACTIVE;
        startTime = block.timestamp; // countdown begins
        _emitConfig();
    }

    ///@notice allows an admin to fund a raffle with ERC20 tokens
    function fundRaffleWithErc20(uint256 amount, address from) public onlyOwner returns (bool) {
        if (!_canFundOrDonate()) return false;

        if (raffleConfig.payoutType != TokenType.ERC20) return false;

        if (_validateErc20PayoutTokenAddress() == false) revert PayoutTokenAddressNotSet();

        _prizePool += amount;
        totalFunds += amount;

        bool success = payoutToken.transferFrom(from, address(this), amount);

        if (!success) revert InsufficientAllowanceError();

        emit RaffleFunded(amount);
        return success;
    }

    ///@notice allows an admin to fund a raffle with ETH
    function fundRaffleWithEth() public payable onlyOwner returns (bool) {
        if (!_canFundOrDonate()) return false;

        if (raffleConfig.payoutType != TokenType.ETH) return false;

        _prizePool += msg.value;
        totalFunds += msg.value;

        emit RaffleFunded(msg.value);
        return true;
    }

    ///@notice allows a user enter the raffle
    function enterRaffle() public payable isActive {
        // reentry is only allowed for weighted raffles
        if (entries[payable(msg.sender)] != 0 && raffleConfig.raffleType == Type.BALANCED) revert RaffleReentryError();

        raffleParticipants.push(payable(msg.sender));
        entries[payable(msg.sender)] += 1; // increment entry count by 1
        totalEntries += 1;

        // validate and collect payments
        if (raffleConfig.payoutType == TokenType.ERC20) {
            bool success = payoutToken.transferFrom(msg.sender, address(this), raffleConfig.entryFee);
            _prizePool += raffleConfig.entryFee;
            _totalEntryFee += raffleConfig.entryFee;
            if (!success) revert InsufficientAllowanceError();
        } else {
            _prizePool += msg.value;
            _totalEntryFee += msg.value;
            if (msg.value != raffleConfig.entryFee) revert RaffleEntryFeeError();
        }

        emit RaffleEntry(msg.sender, raffleConfig.entryFee, raffleConfig.payoutType);
    }

    ///@notice allows anyone to make ERC20 donations into the raffle when the raffle is active
    function donateErc20(uint256 amount, address from) public {
        if (raffleConfig.state != LifeCycle.ACTIVE) revert DonationError();
        if (raffleConfig.payoutType != TokenType.ERC20) revert PayoutTypeError();
        if (amount < raffleConfig.minimumDonation) revert MinimumDonationError();

        bool success = payoutToken.transferFrom(from, address(this), amount);

        if (!success) revert InsufficientAllowanceError();

        donations[from] += amount;
        _prizePool += amount;

        emit RaffleDonation(from, amount);
    }

    ///@notice allows anyone to make ETH donations into the raffle when the raffle si active
    function donateEth() public payable {
        if (raffleConfig.state != LifeCycle.ACTIVE) revert DonationError();
        if (raffleConfig.payoutType != TokenType.ETH) revert PayoutTypeError();
        if (msg.value < raffleConfig.minimumDonation) revert MinimumDonationError();

        donations[msg.sender] += msg.value;
        _prizePool += msg.value;

        emit RaffleDonation(msg.sender, msg.value);
    }

    ///@notice allows querying raffle details
    function getRaffleDetails()
        public
        view
        returns (LifeCycle state, uint256 prizePool, uint256 entryCount, uint256 endTime, Type raffleType)
    {
        return
            (raffleConfig.state, _prizePool, totalEntries, startTime + raffleConfig.duration, raffleConfig.raffleType);
    }

    ///@notice get donation refunds
    ///@dev
    function getDonationRefunds() public nonReentrant {
        // donors can get refunds if and only if there's no entry into the raffle and the the raffle state is READY_FOR_DRAINAGE
        _updateLifeCycle();
        if (totalEntries != 0 || raffleConfig.state != LifeCycle.READY_FOR_DRAINAGE) {
            revert InvalidDonationRefundError();
        }
        if (donations[msg.sender] == 0) revert InsufficientAllowanceError();
        uint256 amount = donations[msg.sender];
        donations[msg.sender] = 0;
        _prizePool -= amount;
        if (raffleConfig.payoutType == TokenType.ETH) {
            (bool success,) = msg.sender.call{value: amount}("");
            if (!success) revert InsufficientAllowanceError();
        } else {
            bool success = payoutToken.transfer(msg.sender, amount);
            if (!success) revert InsufficientAllowanceError();
        }
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

    ///@notice helper function to update raffleLifecycle
    function _updateLifeCycle() internal {
        if (startTime != 0 && block.timestamp < startTime + raffleConfig.duration) return;

        if (raffleParticipants.length != 0) {
            raffleConfig.state = LifeCycle.READY_FOR_PAYOUT;
        } else {
            raffleConfig.state = LifeCycle.READY_FOR_DRAINAGE;
        }

        _emitConfig();
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

    ///@notice reward the winner with the selected token
    function _rewardWinnerWithErc20(address winner) private returns (bool) {
        if (_prizePool == 0 || _prizePool != payoutToken.balanceOf(address(this))) revert PrizePoolBalanceError();
        uint256 protocolFee = (_prizePool * raffleConfig.protocolPercentage) / 10000;
        uint256 winnerReward = _prizePool - protocolFee;

        _prizePool -= protocolFee;
        // transfer the protocol fee from the raffle contract to the raffle_factory
        bool protocolFeeSent = payoutToken.transfer(RAFFLE_FACTORY, protocolFee);

        if (!protocolFeeSent) revert PayoutError();

        _prizePool -= winnerReward;
        // transfer erc20 to protocol winner
        bool rewardSent = payoutToken.transferFrom(address(this), winner, winnerReward);

        if (!rewardSent) revert PayoutError();
        return true;
    }

    ///@notice reward the winner with the selected token
    function _rewardWinnerWithEth(address payable winner) private nonReentrant returns (bool) {
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

    ///@notice helper function to check if a raffle is fundable
    function _canFundOrDonate() private view returns (bool) {
        if (
            raffleConfig.state == LifeCycle.READY_FOR_DRAINAGE || raffleConfig.state == LifeCycle.READY_FOR_PAYOUT
                || raffleConfig.state == LifeCycle.COMPLETE
        ) return false;

        return true;
    }
}
