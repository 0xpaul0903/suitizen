module suitizen::config{

    const EVersionNotMatched: u64 = 1;

    public struct GlobalConfig has key{ 
        id: UID,
        version: u64,
    }

    public struct AdminCap has key{
        id: UID,
    }

    fun init(ctx: &mut TxContext){

        let admin_cap = AdminCap{
            id: object::new(ctx),
        };

        let config = GlobalConfig{
            id: object::new(ctx),
            version: 1u64,
        };

        transfer::transfer(admin_cap, ctx.sender());
        transfer::share_object(config);
    }

    public fun upgrade(
        config: &mut GlobalConfig,
    ){
        config.version = config.version + 1;
    }

    public(package) fun assert_if_version_not_matched(
        config: &GlobalConfig,
        contract_version: u64,
    ) {
        assert!(config.version == contract_version, EVersionNotMatched);
    }

    
}