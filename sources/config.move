module suitizen::config{

    use sui::{
        table::{Self, Table},
    };

    const EVersionNotMatched: u64 = 1;

    public struct GlobalConfig has key{ 
        id: UID,
        version: u64,
        citizen_amount: u64,
        interaction_state: Table<u64, u64>,
    }

    public struct AdminCap has key{
        id: UID,
    }

    fun init(ctx: &mut TxContext){

        let admin_cap = AdminCap{
            id: object::new(ctx),
        };

        let mut config = GlobalConfig{
            id: object::new(ctx),
            version: 1u64,
            citizen_amount: 0,
            interaction_state: table::new<u64, u64>(ctx),
        };

        config.interaction_state.add(0, 0); // Vote Proposal init to 0
        config.interaction_state.add(1, 0); // Discuss Proposal init to 0

        transfer::transfer(admin_cap, ctx.sender());
        transfer::share_object(config);
    }

    public fun upgrade(
        config: &mut GlobalConfig,
    ){
        config.version = config.version + 1;
    }

    public fun citizen_amount(
        config: &mut GlobalConfig,
    ): u64{
        config.citizen_amount
    }

    public(package) fun interaction_state(
        config: &GlobalConfig,
    ): &Table<u64, u64>{
        &config.interaction_state
    }

    public(package) fun assert_if_version_not_matched(
        config: &GlobalConfig,
        contract_version: u64,
    ) {
        assert!(config.version == contract_version, EVersionNotMatched);
    }

    public(package) fun add_type_amount(
        config: &mut GlobalConfig,
        interaction_type: u64,
    ) {
        let mut amount = config.interaction_state.remove(interaction_type);
        amount = amount +1 ;
        config.interaction_state.add(interaction_type, amount);
    }

    public(package) fun add_suitizen_amount(
        config: &mut GlobalConfig,
    ){
        config.citizen_amount = config.citizen_amount + 1;
    }

    
}