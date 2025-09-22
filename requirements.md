# Raffle System Requirements

## Overview
A decentralized raffle system built on Ethereum using a factory pattern architecture. The system allows users to create and participate in various types of raffles with automated winner selection using Chainlink VRF and automated execution via Chainlink Automation.

## Architecture Overview
- **Factory Contract**: Deploys and manages individual raffle contracts, handles VRF integration and automation
- **Raffle Contract**: Individual raffle instances with their own lifecycle and state management
- **Integration**: Chainlink VRF for provable randomness, Chainlink Automation for automated execution

## User Stories

### As a System Administrator (Factory Owner)
- **US1**: As a system admin, I want to set minimum and maximum raffle durations so I can control raffle timeframes
- **US2**: As a system admin, I want to update duration limits so I can adapt to changing requirements
- **US3**: As a system admin, I want to pause the factory contract so I can halt new raffle creation during emergencies
- **US4**: As a system admin, I want to transfer factory ownership so I can delegate administrative responsibilities
- **US5**: As a system admin, I want to collect 3% fees from all payouts so the platform can be sustainable

### As a Raffle Creator
- **US6**: As a raffle creator, I want to create a new raffle with custom parameters so I can organize my own raffle event
- **US7**: As a raffle creator, I want to fund my raffle's initial prize pool so participants have something to win
- **US8**: As a raffle creator, I want to set minimum entry fees and donation amounts so I can control participation costs
- **US9**: As a raffle creator, I want to choose between weighted and balanced raffle types so I can decide the fairness model
- **US10**: As a raffle creator, I want to drain unfunded raffles to a specific address so I can recover funds if no one participates
- **US11**: As a raffle creator, I want to destroy my completed raffle contract so I can clean up and save network resources
- **US12**: As a raffle creator, I want to refund all participants if my raffle has no entries so everyone gets their money back

### As a Raffle Participant
- **US13**: As a participant, I want to join existing raffles by paying the entry fee so I can have a chance to win
- **US14**: As a participant, I want to make donations to active raffles so I can increase the prize pool
- **US15**: As a participant, I want to view all raffle details using the raffle ID so I can make informed participation decisions
- **US16**: As a participant, I want to receive refunds if a raffle is cancelled so I don't lose my money
- **US17**: As a participant, I want to claim my prize if I win so I can receive my reward

### As a Winner
- **US18**: As a winner, I want to be automatically selected when the raffle ends so the process is fair and transparent
- **US19**: As a winner, I want to claim my prize after selection so I can receive my winnings
- **US20**: As a winner, I want to be the sole winner if I'm the only participant so I don't need to wait for randomness

## Functional Requirements

### Core Raffle Management
**FR1: Raffle Creation**
- Users can create raffles through the factory contract
- Required parameters: duration, entry fee, minimum donation, payout token type, raffle type
- Creator becomes the raffle admin
- Each raffle gets a unique contract address
- Duration must be within admin-defined min/max limits

**FR2: Raffle Funding**
- Raffle creators must fund initial prize pool to activate raffle
- Supports both Ether and ERC20 tokens as payout methods
- Raffle transitions from INACTIVE to ACTIVE state upon funding

**FR3: Raffle Participation**
- Anyone can join active raffles by paying the exact entry fee
- Entry fees are added to the prize pool
- Multiple entries allowed (behavior differs by raffle type)
- Minimum entry fee enforced by raffle creator

**FR4: Raffle Donations**
- Anyone can donate to active raffles above the minimum donation amount
- Donations increase the prize pool
- No entry rights granted for donations

**FR5: Raffle Information Access**
- Anyone can query raffle details by contract address
- Public information includes: state, prize pool, entry count, end time, raffle type

### State Management
**FR6: Raffle State Lifecycle**
```
INACTIVE → ACTIVE → READY_FOR_PAYOUT → COMPLETE
         ↓         ↓
         ↓         READY_FOR_DRAINAGE → COMPLETE
```

- **INACTIVE**: Created but not funded by creator
- **ACTIVE**: Funded and accepting entries/donations
- **READY_FOR_PAYOUT**: Time expired with entries, awaiting winner selection
- **READY_FOR_DRAINAGE**: Time expired with no entries
- **COMPLETE**: Payout completed or funds drained, ready for destruction

**FR7: Automated State Transitions**
- Chainlink Automation triggers state checks
- Automatic transition from ACTIVE to READY_FOR_* states
- Batch processing of multiple raffles in single automation call

### Winner Selection and Payouts
**FR8: Winner Selection Logic**
- Single participant: Automatic winner (no randomness needed)
- Multiple participants: Chainlink VRF for provable randomness
- Weighted raffles: Winner probability based on entry count
- Balanced raffles: Equal probability regardless of entry count

**FR9: Prize Distribution**
- 97% of prize pool goes to winner
- 3% platform fee deducted automatically
- Winners must claim prizes manually
- Unclaimed prizes remain in contract

**FR10: Edge Case Handling**
- No participants: Admin can drain pool to specified address (no fees)
- Failed VRF requests: Retry mechanism or manual intervention
- Single participant: Direct winner assignment

### Factory Contract Management
**FR11: Contract Deployment**
- Factory deploys new raffle contract instances
- Maintains registry of all deployed raffles
- Tracks active, completed, and destroyed raffles

**FR12: VRF Integration**
- Raffle contracts forward VRF requests to factory with unique nonce
- Factory manages VRF subscription and routes responses back
- Nonce mapping prevents collision and ensures proper routing

**FR13: Contract Destruction**
- Only raffle admin can destroy their completed raffle
- Proper cleanup of factory registry mappings
- Contract must be in COMPLETE state for destruction

**FR14: Administrative Controls**
- Factory owner can update min/max duration limits
- Pausable functionality for emergency stops
- Ownership transfer capability

## Non-Functional Requirements

### Performance
**NFR1: Gas Efficiency**
- Raffle entry operations: < 100,000 gas
- Automation upkeep: Process multiple raffles efficiently
- Batch operations where possible
- Minimal storage reads in critical paths

**NFR2: Scalability**
- Support unlimited concurrent raffles
- Efficient iteration through raffle registry
- Gas-limited automation processing (handle large raffle counts)

### Security
**NFR3: Randomness Security**
- Use Chainlink VRF for cryptographically secure randomness
- Prevent VRF manipulation or prediction
- Nonce collision prevention in VRF requests

**NFR4: Access Control**
- Role-based permissions (factory owner, raffle admin)
- Reentrancy protection on all state-changing functions
- Input validation on all external functions

**NFR5: Contract Security**
- Emergency pause functionality
- Safe arithmetic operations
- Proper event emission for transparency

### Reliability
**NFR6: Error Handling**
- Graceful handling of failed VRF requests
- Retry mechanisms for critical operations
- Clear error messages for failed transactions

**NFR7: State Consistency**
- Atomic state transitions
- Prevention of invalid state combinations
- Consistent behavior across network congestion

### Usability
**NFR8: Transparency**
- All raffle parameters publicly visible
- Event emission for all significant state changes
- Verifiable randomness and winner selection

**NFR9: Integration**
- Clean interfaces for frontend integration
- Standardized event schemas
- Support for common wallet integrations

## Technical Requirements

### Blockchain Integration
**TR1: Chainlink VRF Integration**
- VRF requests routed through factory contract
- Unique nonce system for request tracking
- Callback handling for randomness fulfillment
- Gas-efficient request batching

**TR2: Chainlink Automation Integration**
- Automated raffle state checking
- Batch processing of ready raffles
- Gas limit awareness for upkeep functions
- Conditional execution based on raffle states

**TR3: Token Support**
- Native Ether support for prizes and fees
- ERC20 token support for prizes
- Proper token transfer handling
- Token approval requirements

### Smart Contract Architecture
**TR4: Factory Pattern Implementation**
- Minimal proxy pattern for gas-efficient deployment
- Contract registry maintenance
- Proper initialization of deployed contracts
- Interface standardization between factory and raffles

**TR5: State Management**
- Enum-based state tracking
- State transition validation
- Event-driven state change notifications
- Time-based state evaluation

**TR6: Data Structures**
```solidity
struct RaffleParams {
    uint256 duration;
    uint256 entryFee;
    uint256 minDonation;
    address payoutToken;
    bool isWeighted;
}

struct RaffleInfo {
    address creator;
    RaffleState state;
    uint256 prizePool;
    uint256 entryCount;
    uint256 endTime;
    address winner;
}
```

## Business Rules

### Timing Rules
**BR1**: Minimum raffle duration: Configurable by factory owner (default: 1 hour)
**BR2**: Maximum raffle duration: Configurable by factory owner (default: 30 days)
**BR3**: Raffle end time is immutable once set during creation

### Financial Rules
**BR4**: Platform fee: 3% of all payouts (not applied to drained pools)
**BR5**: Minimum entry fee: Set by raffle creator (must be > 0)
**BR6**: Minimum donation: Set by raffle creator (can be 0)
**BR7**: Prize pool accumulates all entry fees and donations

### Operational Rules
**BR8**: One winner per raffle (no tie-breaking needed)
**BR9**: Raffles are single-use (cannot be restarted or reused)
**BR10**: Factory can be paused by owner (prevents new raffle creation)
**BR11**: VRF requests timeout after 24 hours (manual intervention required)

## Edge Cases and Error Handling

### Participant Edge Cases
**EC1**: No participants - Admin can drain pool, no fees collected
**EC2**: Single participant - Automatic winner, no VRF needed
**EC3**: VRF failure - Implement retry mechanism or manual override

### Financial Edge Cases
**EC4**: Insufficient funds for fees - Transaction reverts
**EC5**: Token transfer failures - Proper error handling and rollback
**EC6**: Prize claiming failures - Funds remain in contract

### System Edge Cases
**EC7**: Factory pause during active raffles - Existing raffles continue, no new creation
**EC8**: Automation failure - Manual trigger capability required
**EC9**: Contract destruction with funds - Prevented by state checks

## Success Metrics

### Functional Metrics
- Successful raffle creation rate: > 99%
- Successful entry processing rate: > 99%
- Successful winner selection rate: > 99%
- Successful prize distribution rate: > 95%

### Performance Metrics
- Average gas cost per raffle entry: < 100,000 gas
- Automation upkeep gas usage: < 500,000 gas per call
- VRF fulfillment time: < 5 minutes average

### Security Metrics
- Zero successful attacks on randomness
- Zero unauthorized access incidents
- Zero fund loss incidents due to smart contract bugs

## Future Enhancements

### Phase 2 Features
- Multi-winner raffles
- Recurring raffles
- NFT prize support
- Cross-chain compatibility

### Phase 3 Features
- Raffle templates
- Social features (comments, sharing)
- Advanced analytics
- DAO governance integration