/*
 * Copyright (c) 2024 Bima Kharisma Wicaksana
 * GitHub: https://github.com/bimakw
 *
 * Licensed under MIT License with Attribution Requirement.
 * See LICENSE file for details.
 */

/// Treasury Module - DAO treasury management with multi-sig style governance.
/// Controls DAO funds with proposal-based spending.
module sui_dao::treasury {
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::event;
    use sui::table::{Self, Table};
    use std::string::{Self, String};

    /// Error codes
    const ENotAuthorized: u64 = 0;
    const EInsufficientFunds: u64 = 1;
    const ESpendingProposalNotApproved: u64 = 2;
    const EProposalAlreadyProcessed: u64 = 3;
    const ENotEnoughApprovals: u64 = 4;

    /// Spending proposal status
    const STATUS_PENDING: u8 = 0;
    const STATUS_APPROVED: u8 = 1;
    const STATUS_REJECTED: u8 = 2;
    const STATUS_EXECUTED: u8 = 3;

    /// Treasury
    public struct Treasury has key {
        id: UID,
        balance: Balance<SUI>,
        /// Required approvals for spending
        required_approvals: u64,
        /// List of treasury signers
        signers: vector<address>,
        /// Total spending proposals
        proposal_count: u64,
    }

    /// Signer capability
    public struct SignerCap has key, store {
        id: UID,
        treasury_id: ID,
        signer: address,
    }

    /// Spending proposal
    public struct SpendingProposal has key, store {
        id: UID,
        proposal_id: u64,
        treasury_id: ID,
        proposer: address,
        recipient: address,
        amount: u64,
        description: String,
        approvals: Table<address, bool>,
        approval_count: u64,
        status: u8,
    }

    /// Events
    public struct TreasuryCreated has copy, drop {
        treasury_id: ID,
        required_approvals: u64,
        signers: vector<address>,
    }

    public struct FundsDeposited has copy, drop {
        treasury_id: ID,
        depositor: address,
        amount: u64,
    }

    public struct SpendingProposalCreated has copy, drop {
        proposal_id: u64,
        proposer: address,
        recipient: address,
        amount: u64,
    }

    public struct ProposalApproved has copy, drop {
        proposal_id: u64,
        approver: address,
        approval_count: u64,
    }

    public struct SpendingExecuted has copy, drop {
        proposal_id: u64,
        recipient: address,
        amount: u64,
    }

    /// Create a new treasury with multi-sig
    public entry fun create_treasury(
        signers: vector<address>,
        required_approvals: u64,
        ctx: &mut TxContext
    ) {
        assert!(required_approvals <= vector::length(&signers), ENotAuthorized);
        assert!(required_approvals > 0, ENotAuthorized);

        let treasury = Treasury {
            id: object::new(ctx),
            balance: balance::zero(),
            required_approvals,
            signers: signers,
            proposal_count: 0,
        };

        let treasury_id = object::id(&treasury);

        // Create signer capabilities
        let mut i = 0;
        let len = vector::length(&signers);
        while (i < len) {
            let signer_addr = *vector::borrow(&signers, i);
            let cap = SignerCap {
                id: object::new(ctx),
                treasury_id,
                signer: signer_addr,
            };
            transfer::transfer(cap, signer_addr);
            i = i + 1;
        };

        event::emit(TreasuryCreated {
            treasury_id,
            required_approvals,
            signers,
        });

        transfer::share_object(treasury);
    }

    /// Deposit funds to treasury
    public entry fun deposit(
        treasury: &mut Treasury,
        payment: Coin<SUI>,
        ctx: &TxContext
    ) {
        let amount = coin::value(&payment);
        let depositor = tx_context::sender(ctx);

        balance::join(&mut treasury.balance, coin::into_balance(payment));

        event::emit(FundsDeposited {
            treasury_id: object::id(treasury),
            depositor,
            amount,
        });
    }

    /// Create spending proposal (signer only)
    public entry fun create_spending_proposal(
        treasury: &mut Treasury,
        signer_cap: &SignerCap,
        recipient: address,
        amount: u64,
        description: vector<u8>,
        ctx: &mut TxContext
    ) {
        assert!(signer_cap.treasury_id == object::id(treasury), ENotAuthorized);
        assert!(balance::value(&treasury.balance) >= amount, EInsufficientFunds);

        treasury.proposal_count = treasury.proposal_count + 1;
        let proposal_id = treasury.proposal_count;
        let proposer = tx_context::sender(ctx);

        let mut proposal = SpendingProposal {
            id: object::new(ctx),
            proposal_id,
            treasury_id: object::id(treasury),
            proposer,
            recipient,
            amount,
            description: string::utf8(description),
            approvals: table::new(ctx),
            approval_count: 0,
            status: STATUS_PENDING,
        };

        // Auto-approve by proposer
        table::add(&mut proposal.approvals, proposer, true);
        proposal.approval_count = 1;

        event::emit(SpendingProposalCreated {
            proposal_id,
            proposer,
            recipient,
            amount,
        });

        event::emit(ProposalApproved {
            proposal_id,
            approver: proposer,
            approval_count: 1,
        });

        transfer::share_object(proposal);
    }

    /// Approve spending proposal (signer only)
    public entry fun approve_proposal(
        treasury: &Treasury,
        proposal: &mut SpendingProposal,
        signer_cap: &SignerCap,
        ctx: &TxContext
    ) {
        let approver = tx_context::sender(ctx);

        assert!(signer_cap.treasury_id == object::id(treasury), ENotAuthorized);
        assert!(proposal.treasury_id == object::id(treasury), ENotAuthorized);
        assert!(proposal.status == STATUS_PENDING, EProposalAlreadyProcessed);
        assert!(!table::contains(&proposal.approvals, approver), EProposalAlreadyProcessed);

        table::add(&mut proposal.approvals, approver, true);
        proposal.approval_count = proposal.approval_count + 1;

        event::emit(ProposalApproved {
            proposal_id: proposal.proposal_id,
            approver,
            approval_count: proposal.approval_count,
        });

        // Auto-approve if threshold reached
        if (proposal.approval_count >= treasury.required_approvals) {
            proposal.status = STATUS_APPROVED;
        };
    }

    /// Execute approved spending proposal
    public entry fun execute_spending(
        treasury: &mut Treasury,
        proposal: &mut SpendingProposal,
        ctx: &mut TxContext
    ) {
        assert!(proposal.treasury_id == object::id(treasury), ENotAuthorized);
        assert!(proposal.status == STATUS_APPROVED, ESpendingProposalNotApproved);
        assert!(proposal.approval_count >= treasury.required_approvals, ENotEnoughApprovals);
        assert!(balance::value(&treasury.balance) >= proposal.amount, EInsufficientFunds);

        proposal.status = STATUS_EXECUTED;

        let payment = coin::from_balance(
            balance::split(&mut treasury.balance, proposal.amount),
            ctx
        );

        event::emit(SpendingExecuted {
            proposal_id: proposal.proposal_id,
            recipient: proposal.recipient,
            amount: proposal.amount,
        });

        transfer::public_transfer(payment, proposal.recipient);
    }

    /// Reject proposal (requires majority of signers to reject)
    public entry fun reject_proposal(
        treasury: &Treasury,
        proposal: &mut SpendingProposal,
        signer_cap: &SignerCap,
        ctx: &TxContext
    ) {
        assert!(signer_cap.treasury_id == object::id(treasury), ENotAuthorized);
        assert!(proposal.treasury_id == object::id(treasury), ENotAuthorized);
        assert!(proposal.status == STATUS_PENDING, EProposalAlreadyProcessed);

        // For simplicity, any signer can reject
        // In production, might require majority rejection
        proposal.status = STATUS_REJECTED;
    }

    /// View functions
    public fun treasury_balance(treasury: &Treasury): u64 {
        balance::value(&treasury.balance)
    }

    public fun required_approvals(treasury: &Treasury): u64 {
        treasury.required_approvals
    }

    public fun proposal_approval_count(proposal: &SpendingProposal): u64 {
        proposal.approval_count
    }

    public fun proposal_status(proposal: &SpendingProposal): u8 {
        proposal.status
    }

    public fun is_signer(treasury: &Treasury, addr: address): bool {
        vector::contains(&treasury.signers, &addr)
    }

    public fun has_approved(proposal: &SpendingProposal, addr: address): bool {
        table::contains(&proposal.approvals, addr)
    }
}
