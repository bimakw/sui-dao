module sui_dao::dao {
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::clock::{Self, Clock};
    use sui::event;
    use sui::table::{Self, Table};
    use std::string::{Self, String};

    use sui_dao::governance_token::{Self, GovernanceConfig};

    const EProposalNotActive: u64 = 0;
    const EAlreadyVoted: u64 = 1;
    const EInsufficientVotingPower: u64 = 2;
    const EVotingNotEnded: u64 = 3;
    const EProposalNotPassed: u64 = 4;
    const EAlreadyExecuted: u64 = 5;
    const EQuorumNotReached: u64 = 6;
    const EProposalExpired: u64 = 7;
    const EBelowProposalThreshold: u64 = 8;

    const STATE_PENDING: u8 = 0;
    const STATE_ACTIVE: u8 = 1;
    const STATE_DEFEATED: u8 = 2;
    const STATE_SUCCEEDED: u8 = 3;
    const STATE_EXECUTED: u8 = 4;
    const STATE_EXPIRED: u8 = 5;

    public struct DAOConfig has key {
        id: UID,
        name: String,
        proposal_threshold: u64,
        quorum_bps: u64,
        voting_period_ms: u64,
        execution_delay_ms: u64,
        execution_window_ms: u64,
        proposal_count: u64,
    }

    public struct Proposal has key, store {
        id: UID,
        proposal_id: u64,
        proposer: address,
        title: String,
        description: String,
        for_votes: u64,
        against_votes: u64,
        abstain_votes: u64,
        total_voting_power_snapshot: u64,
        start_time: u64,
        end_time: u64,
        voters: Table<address, bool>,
        state: u8,
        execution_time: u64,
    }

    public struct VoteReceipt has key, store {
        id: UID,
        proposal_id: u64,
        voter: address,
        support: u8, // 0 = against, 1 = for, 2 = abstain
        votes: u64,
    }

    public struct ProposalCreated has copy, drop {
        proposal_id: u64,
        proposer: address,
        title: String,
        start_time: u64,
        end_time: u64,
    }

    public struct VoteCast has copy, drop {
        proposal_id: u64,
        voter: address,
        support: u8,
        votes: u64,
    }

    public struct ProposalExecuted has copy, drop {
        proposal_id: u64,
        executor: address,
    }

    public struct ProposalStateChanged has copy, drop {
        proposal_id: u64,
        old_state: u8,
        new_state: u8,
    }

    public entry fun create_dao(
        name: vector<u8>,
        proposal_threshold: u64,
        quorum_bps: u64,
        voting_period_ms: u64,
        execution_delay_ms: u64,
        execution_window_ms: u64,
        ctx: &mut TxContext
    ) {
        let dao = DAOConfig {
            id: object::new(ctx),
            name: string::utf8(name),
            proposal_threshold,
            quorum_bps,
            voting_period_ms,
            execution_delay_ms,
            execution_window_ms,
            proposal_count: 0,
        };

        transfer::share_object(dao);
    }

    public entry fun create_proposal(
        dao: &mut DAOConfig,
        gov_config: &GovernanceConfig,
        title: vector<u8>,
        description: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let proposer = tx_context::sender(ctx);
        let voting_power = governance_token::get_voting_power(gov_config, proposer);

        assert!(voting_power >= dao.proposal_threshold, EBelowProposalThreshold);

        let current_time = clock::timestamp_ms(clock);
        let start_time = current_time;
        let end_time = current_time + dao.voting_period_ms;

        dao.proposal_count = dao.proposal_count + 1;
        let proposal_id = dao.proposal_count;

        let proposal = Proposal {
            id: object::new(ctx),
            proposal_id,
            proposer,
            title: string::utf8(title),
            description: string::utf8(description),
            for_votes: 0,
            against_votes: 0,
            abstain_votes: 0,
            total_voting_power_snapshot: governance_token::total_voting_power(gov_config),
            start_time,
            end_time,
            voters: table::new(ctx),
            state: STATE_ACTIVE,
            execution_time: 0,
        };

        event::emit(ProposalCreated {
            proposal_id,
            proposer,
            title: proposal.title,
            start_time,
            end_time,
        });

        transfer::share_object(proposal);
    }

    public entry fun cast_vote(
        proposal: &mut Proposal,
        gov_config: &GovernanceConfig,
        support: u8, // 0 = against, 1 = for, 2 = abstain
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let voter = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);

        assert!(proposal.state == STATE_ACTIVE, EProposalNotActive);
        assert!(current_time >= proposal.start_time, EProposalNotActive);
        assert!(current_time < proposal.end_time, EProposalNotActive);

        assert!(!table::contains(&proposal.voters, voter), EAlreadyVoted);

        let votes = governance_token::get_voting_power(gov_config, voter);
        assert!(votes > 0, EInsufficientVotingPower);

        table::add(&mut proposal.voters, voter, true);

        if (support == 0) {
            proposal.against_votes = proposal.against_votes + votes;
        } else if (support == 1) {
            proposal.for_votes = proposal.for_votes + votes;
        } else {
            proposal.abstain_votes = proposal.abstain_votes + votes;
        };

        event::emit(VoteCast {
            proposal_id: proposal.proposal_id,
            voter,
            support,
            votes,
        });

        let receipt = VoteReceipt {
            id: object::new(ctx),
            proposal_id: proposal.proposal_id,
            voter,
            support,
            votes,
        };

        transfer::transfer(receipt, voter);
    }

    public entry fun finalize_proposal(
        dao: &DAOConfig,
        proposal: &mut Proposal,
        clock: &Clock
    ) {
        let current_time = clock::timestamp_ms(clock);

        assert!(proposal.state == STATE_ACTIVE, EProposalNotActive);
        assert!(current_time >= proposal.end_time, EVotingNotEnded);

        let old_state = proposal.state;
        let total_votes = proposal.for_votes + proposal.against_votes + proposal.abstain_votes;

        let quorum_votes = (proposal.total_voting_power_snapshot * dao.quorum_bps) / 10000;

        if (total_votes < quorum_votes) {
            proposal.state = STATE_DEFEATED;
        } else if (proposal.for_votes > proposal.against_votes) {
            proposal.state = STATE_SUCCEEDED;
            proposal.execution_time = current_time + dao.execution_delay_ms;
        } else {
            proposal.state = STATE_DEFEATED;
        };

        event::emit(ProposalStateChanged {
            proposal_id: proposal.proposal_id,
            old_state,
            new_state: proposal.state,
        });
    }

    public entry fun execute_proposal(
        dao: &DAOConfig,
        proposal: &mut Proposal,
        clock: &Clock,
        ctx: &TxContext
    ) {
        let current_time = clock::timestamp_ms(clock);
        let executor = tx_context::sender(ctx);

        assert!(proposal.state == STATE_SUCCEEDED, EProposalNotPassed);
        assert!(current_time >= proposal.execution_time, EVotingNotEnded);

        let execution_deadline = proposal.execution_time + dao.execution_window_ms;
        assert!(current_time <= execution_deadline, EProposalExpired);

        let old_state = proposal.state;
        proposal.state = STATE_EXECUTED;

        event::emit(ProposalStateChanged {
            proposal_id: proposal.proposal_id,
            old_state,
            new_state: proposal.state,
        });

        event::emit(ProposalExecuted {
            proposal_id: proposal.proposal_id,
            executor,
        });

        // NOTE: In a real implementation, this would trigger
        // the actual on-chain actions defined in the proposal
    }

    public entry fun expire_proposal(
        dao: &DAOConfig,
        proposal: &mut Proposal,
        clock: &Clock
    ) {
        let current_time = clock::timestamp_ms(clock);

        assert!(proposal.state == STATE_SUCCEEDED, EProposalNotPassed);

        let execution_deadline = proposal.execution_time + dao.execution_window_ms;
        assert!(current_time > execution_deadline, EVotingNotEnded);

        let old_state = proposal.state;
        proposal.state = STATE_EXPIRED;

        event::emit(ProposalStateChanged {
            proposal_id: proposal.proposal_id,
            old_state,
            new_state: proposal.state,
        });
    }

    public fun get_proposal_state(proposal: &Proposal): u8 {
        proposal.state
    }

    public fun get_vote_counts(proposal: &Proposal): (u64, u64, u64) {
        (proposal.for_votes, proposal.against_votes, proposal.abstain_votes)
    }

    public fun has_voted(proposal: &Proposal, voter: address): bool {
        table::contains(&proposal.voters, voter)
    }

    public fun get_quorum_votes(dao: &DAOConfig, proposal: &Proposal): u64 {
        (proposal.total_voting_power_snapshot * dao.quorum_bps) / 10000
    }

    public fun is_quorum_reached(dao: &DAOConfig, proposal: &Proposal): bool {
        let total_votes = proposal.for_votes + proposal.against_votes + proposal.abstain_votes;
        total_votes >= get_quorum_votes(dao, proposal)
    }

    public fun proposal_count(dao: &DAOConfig): u64 {
        dao.proposal_count
    }

    public fun state_to_string(state: u8): String {
        if (state == STATE_PENDING) {
            string::utf8(b"Pending")
        } else if (state == STATE_ACTIVE) {
            string::utf8(b"Active")
        } else if (state == STATE_DEFEATED) {
            string::utf8(b"Defeated")
        } else if (state == STATE_SUCCEEDED) {
            string::utf8(b"Succeeded")
        } else if (state == STATE_EXECUTED) {
            string::utf8(b"Executed")
        } else {
            string::utf8(b"Expired")
        }
    }
}
