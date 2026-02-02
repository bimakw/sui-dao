/*
 * Copyright (c) 2025 Bima Kharisma Wicaksana
 * GitHub: https://github.com/bimakw
 *
 * Licensed under MIT License with Attribution Requirement.
 * See LICENSE file for details.
 */

/// Governance Token - Token with voting power for DAO governance.
/// Supports delegation and vote checkpointing.
module sui_dao::governance_token {
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::object::{Self, UID};
    use sui::table::{Self, Table};
    use sui::event;

    /// One-Time-Witness
    public struct GOVERNANCE_TOKEN has drop {}

    /// Error codes
    const ENotDelegated: u64 = 0;
    const EAlreadyDelegated: u64 = 1;
    const ESelfDelegation: u64 = 2;

    /// Governance token configuration
    public struct GovernanceConfig has key {
        id: UID,
        /// Mapping of address to their voting power
        voting_power: Table<address, u64>,
        /// Mapping of delegator to delegate
        delegations: Table<address, address>,
        /// Total voting power in circulation
        total_voting_power: u64,
    }

    /// Events
    public struct VotingPowerChanged has copy, drop {
        account: address,
        old_power: u64,
        new_power: u64,
    }

    public struct DelegateChanged has copy, drop {
        delegator: address,
        old_delegate: address,
        new_delegate: address,
    }

    /// Initialize governance token
    fun init(witness: GOVERNANCE_TOKEN, ctx: &mut TxContext) {
        let (treasury_cap, metadata) = coin::create_currency(
            witness,
            9,
            b"GOV",
            b"Governance Token",
            b"DAO governance token with voting power",
            option::none(),
            ctx
        );

        let config = GovernanceConfig {
            id: object::new(ctx),
            voting_power: table::new(ctx),
            delegations: table::new(ctx),
            total_voting_power: 0,
        };

        transfer::public_freeze_object(metadata);
        transfer::public_transfer(treasury_cap, tx_context::sender(ctx));
        transfer::share_object(config);
    }

    /// Get voting power for an account
    public fun get_voting_power(config: &GovernanceConfig, account: address): u64 {
        if (table::contains(&config.voting_power, account)) {
            *table::borrow(&config.voting_power, account)
        } else {
            0
        }
    }

    /// Get delegate for an account
    public fun get_delegate(config: &GovernanceConfig, account: address): address {
        if (table::contains(&config.delegations, account)) {
            *table::borrow(&config.delegations, account)
        } else {
            account // Self-delegated by default
        }
    }

    /// Update voting power (internal)
    fun update_voting_power(
        config: &mut GovernanceConfig,
        account: address,
        delta: u64,
        increase: bool
    ) {
        let old_power = get_voting_power(config, account);
        let new_power = if (increase) {
            old_power + delta
        } else {
            if (old_power >= delta) { old_power - delta } else { 0 }
        };

        if (table::contains(&config.voting_power, account)) {
            *table::borrow_mut(&mut config.voting_power, account) = new_power;
        } else {
            table::add(&mut config.voting_power, account, new_power);
        };

        event::emit(VotingPowerChanged {
            account,
            old_power,
            new_power,
        });
    }

    /// Mint governance tokens
    public entry fun mint(
        treasury_cap: &mut TreasuryCap<GOVERNANCE_TOKEN>,
        config: &mut GovernanceConfig,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext
    ) {
        let coin = coin::mint(treasury_cap, amount, ctx);

        // Update voting power for recipient (or their delegate)
        let delegate = get_delegate(config, recipient);
        update_voting_power(config, delegate, amount, true);
        config.total_voting_power = config.total_voting_power + amount;

        transfer::public_transfer(coin, recipient);
    }

    /// Transfer tokens with voting power update
    public entry fun transfer_token(
        config: &mut GovernanceConfig,
        token: Coin<GOVERNANCE_TOKEN>,
        recipient: address,
        ctx: &TxContext
    ) {
        let amount = coin::value(&token);
        let sender = tx_context::sender(ctx);

        // Update voting power
        let sender_delegate = get_delegate(config, sender);
        let recipient_delegate = get_delegate(config, recipient);

        update_voting_power(config, sender_delegate, amount, false);
        update_voting_power(config, recipient_delegate, amount, true);

        transfer::public_transfer(token, recipient);
    }

    /// Delegate voting power to another address
    public entry fun delegate(
        config: &mut GovernanceConfig,
        tokens: &Coin<GOVERNANCE_TOKEN>,
        delegate_to: address,
        ctx: &TxContext
    ) {
        let delegator = tx_context::sender(ctx);
        let amount = coin::value(tokens);

        assert!(delegator != delegate_to, ESelfDelegation);

        let old_delegate = get_delegate(config, delegator);

        // Move voting power from old delegate to new delegate
        update_voting_power(config, old_delegate, amount, false);
        update_voting_power(config, delegate_to, amount, true);

        // Update delegation mapping
        if (table::contains(&config.delegations, delegator)) {
            *table::borrow_mut(&mut config.delegations, delegator) = delegate_to;
        } else {
            table::add(&mut config.delegations, delegator, delegate_to);
        };

        event::emit(DelegateChanged {
            delegator,
            old_delegate,
            new_delegate: delegate_to,
        });
    }

    /// Remove delegation (self-delegate)
    public entry fun undelegate(
        config: &mut GovernanceConfig,
        tokens: &Coin<GOVERNANCE_TOKEN>,
        ctx: &TxContext
    ) {
        let delegator = tx_context::sender(ctx);
        let amount = coin::value(tokens);

        assert!(table::contains(&config.delegations, delegator), ENotDelegated);

        let old_delegate = *table::borrow(&config.delegations, delegator);

        // Move voting power back to self
        update_voting_power(config, old_delegate, amount, false);
        update_voting_power(config, delegator, amount, true);

        // Remove delegation
        table::remove(&mut config.delegations, delegator);

        event::emit(DelegateChanged {
            delegator,
            old_delegate,
            new_delegate: delegator,
        });
    }

    /// View functions
    public fun total_voting_power(config: &GovernanceConfig): u64 {
        config.total_voting_power
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(GOVERNANCE_TOKEN {}, ctx);
    }
}
