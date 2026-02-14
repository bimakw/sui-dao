module sui_dao::governance_token {
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::object::{Self, UID};
    use sui::table::{Self, Table};
    use sui::event;

    public struct GOVERNANCE_TOKEN has drop {}

    const ENotDelegated: u64 = 0;
    const EAlreadyDelegated: u64 = 1;
    const ESelfDelegation: u64 = 2;

    public struct GovernanceConfig has key {
        id: UID,
        voting_power: Table<address, u64>,
        delegations: Table<address, address>,
        total_voting_power: u64,
    }

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

    public fun get_voting_power(config: &GovernanceConfig, account: address): u64 {
        if (table::contains(&config.voting_power, account)) {
            *table::borrow(&config.voting_power, account)
        } else {
            0
        }
    }

    public fun get_delegate(config: &GovernanceConfig, account: address): address {
        if (table::contains(&config.delegations, account)) {
            *table::borrow(&config.delegations, account)
        } else {
            account // Self-delegated by default
        }
    }

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

    public entry fun mint(
        treasury_cap: &mut TreasuryCap<GOVERNANCE_TOKEN>,
        config: &mut GovernanceConfig,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext
    ) {
        let coin = coin::mint(treasury_cap, amount, ctx);

        let delegate = get_delegate(config, recipient);
        update_voting_power(config, delegate, amount, true);
        config.total_voting_power = config.total_voting_power + amount;

        transfer::public_transfer(coin, recipient);
    }

    public entry fun transfer_token(
        config: &mut GovernanceConfig,
        token: Coin<GOVERNANCE_TOKEN>,
        recipient: address,
        ctx: &TxContext
    ) {
        let amount = coin::value(&token);
        let sender = tx_context::sender(ctx);

        let sender_delegate = get_delegate(config, sender);
        let recipient_delegate = get_delegate(config, recipient);

        update_voting_power(config, sender_delegate, amount, false);
        update_voting_power(config, recipient_delegate, amount, true);

        transfer::public_transfer(token, recipient);
    }

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

        update_voting_power(config, old_delegate, amount, false);
        update_voting_power(config, delegate_to, amount, true);

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

    public entry fun undelegate(
        config: &mut GovernanceConfig,
        tokens: &Coin<GOVERNANCE_TOKEN>,
        ctx: &TxContext
    ) {
        let delegator = tx_context::sender(ctx);
        let amount = coin::value(tokens);

        assert!(table::contains(&config.delegations, delegator), ENotDelegated);

        let old_delegate = *table::borrow(&config.delegations, delegator);

        update_voting_power(config, old_delegate, amount, false);
        update_voting_power(config, delegator, amount, true);

        table::remove(&mut config.delegations, delegator);

        event::emit(DelegateChanged {
            delegator,
            old_delegate,
            new_delegate: delegator,
        });
    }

    public fun total_voting_power(config: &GovernanceConfig): u64 {
        config.total_voting_power
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(GOVERNANCE_TOKEN {}, ctx);
    }
}
