module suitizen::suitizen {
    use std::{
        string::{Self, String},
    };
    use sui::{
        table:: {Self, Table,},
        package,
        display,
        balance::{Self, Balance},
        coin::{Self, Coin},
        sui::{SUI},
        dynamic_object_field as dof, 
        clock::{Clock},
    };

    use suins::suins_registration::{SuinsRegistration};
    use suitizen::config::{Self, GlobalConfig, AdminCap};

    public struct SUITIZEN has drop{}

    const EDuplicateAssign: u64 = 0;
    const ENameServiceAlreadyUsed: u64 = 1;
    const EFaceAlreadyUsed: u64 = 2;
    const EPfpAlreadyUsed: u64 = 3;
    const ENsExpired: u64 = 4;
    const ENoNsBoound:u64 = 5;
    const EBalanceNotMatched: u64 = 6;
    

    const VERSION: u64 = 1;

    public struct Treasury has key {
        id: UID,
        register_fee: u64,// unit: mist
        balance: Balance<SUI>,
    }

    public struct Registry has key{
        id: UID,
        reg_tab: Table<vector<u8>, ID>,
        face_tab: Table<String, ID>,
        pfp_tab: Table<u64, String>,
    }

    public struct SuitizenCard has key{
        // sui ns need to be dynamic field
        id: UID,
        last_name: String,
        first_name: String,
        card_img: String, // blob id 
        face_feature: String  // blob id 
    }

    public struct Name has copy, store, drop {}
    
    #[allow(lint(share_owned))]
    fun init (otw: SUITIZEN, ctx: &mut TxContext){
        let registry = Registry{
            id: object::new(ctx),
            reg_tab: table::new<vector<u8>, ID>(ctx),
            face_tab: table::new<String, ID>(ctx),
            pfp_tab: table::new<u64, String>(ctx),
        };

        let treasury = Treasury{
            id: object::new(ctx),
            register_fee: 100000000, // register fee : 0.1 SUI
            balance: balance::zero<SUI>(),
        };

        // setup Kapy display
        let keys = vector[
            string::utf8(b"name"),
            string::utf8(b"description"),
            string::utf8(b"image_url"),
            string::utf8(b"project_url"),
        ];

        let values = vector[
            // name
            string::utf8(b"Suitizen: {first_name} {last_name}"),
            // description
            string::utf8(b"A Citizen of the SUI World"),
            // image_url
            string::utf8(b"https://aggregator-devnet.walrus.space/v1/{card_img}"),
            // project_url
            string::utf8(b"https://github.com/0xpaul0903/suitizen"),
        ];

        let deployer = ctx.sender();
        let publisher = package::claim(otw, ctx);
        let mut displayer = display::new_with_fields<SuitizenCard>(
            &publisher, keys, values, ctx,
        );

        display::update_version(&mut displayer);

        transfer::public_transfer(displayer, deployer);
        transfer::public_transfer(publisher, deployer);
        
        transfer::share_object(registry);
        transfer::share_object(treasury);
    } 

    public entry fun mint(
        config: &GlobalConfig,
        registry: &mut Registry,
        treasury: &mut Treasury,
        sui_ns: SuinsRegistration,
        index: u64,
        pfp_img: String, // blob id
        card_img: String, // blob id 
        face_feature: String, // blob id 
        coin: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let id_card = create_card(config, registry, treasury,  sui_ns, index, pfp_img, card_img, face_feature, coin.into_balance(), clock, ctx);
        transfer::transfer(id_card, ctx.sender())
    }

    public fun create_card(
        config: &GlobalConfig,
        registry: &mut Registry,
        treasury: &mut Treasury, 
        sui_ns: SuinsRegistration,
        index: u64,
        pfp_img: String, // blob id 
        card_img: String, // blob id 
        face_feature: String, // blob id 
        balance: Balance<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) : SuitizenCard{

        config::assert_if_version_not_matched(config, VERSION);

        assert_if_ns_expired_by_ns(&sui_ns, clock);
        assert_if_face_existed(registry, face_feature);
        assert_if_name_existed(registry, &sui_ns);
        assert_if_index_existed(registry, index);
        assert_if_balance_not_matched(treasury, &balance);

        let first_name = *sui_ns.domain().tld();
        let last_name =  *sui_ns.domain().sld();
        
        let mut name = string::utf8(b"");
        name.append( first_name);
        name.append(last_name);

        let mut card = SuitizenCard{
            id: object::new(ctx),
            first_name, 
            last_name,
            card_img,
            face_feature,
        };

        
        registry.reg_tab.add(name.into_bytes(), card.id.uid_to_inner());
        registry.face_tab.add(face_feature, card.id.uid_to_inner());
        registry.pfp_tab.add(index, pfp_img);
        
        dof::add<Name, SuinsRegistration>(&mut card.id, Name{}, sui_ns);

        treasury.balance.join(balance);
        
        card
    }

    #[allow(lint(self_transfer))]
    public fun rename (
        config: &GlobalConfig,
        registry: &mut Registry,
        sui_ns: SuinsRegistration,
        card: &mut SuitizenCard,
        ctx: &mut TxContext,
    ){
        config::assert_if_version_not_matched(config, VERSION);

        assert_if_no_ns(card);

        let new_first_name = *sui_ns.domain().sld();
        let new_last_name = *sui_ns.domain().tld();
        
        if ((*card.first_name.as_bytes() == *new_first_name.as_bytes()) &&
            (*card.last_name.as_bytes() == *new_last_name.as_bytes())
        ){
            abort EDuplicateAssign
        }else{

            let mut name = string::utf8(b"");
            name.append( card.first_name);
            name.append(card.last_name);

            registry.reg_tab.remove(*name.as_bytes());
            
            card.first_name = new_first_name;
            card.last_name = new_last_name;

            name = string::utf8(b"");
            name.append( card.first_name);
            name.append(card.last_name);

            registry.reg_tab.add(*name.as_bytes(), card.id.to_inner());

            let old_ns = dof::remove<Name, SuinsRegistration>(&mut card.id, Name{});
            dof::add<Name, SuinsRegistration>(&mut card.id, Name{}, sui_ns);

            transfer::public_transfer(old_ns, ctx.sender());
            
        };
    }

    public fun first_name(
        card: &SuitizenCard,
    ): String{
        card.first_name
    }

    public fun last_name(
        card: &SuitizenCard,
    ): String{
        card.first_name
    }

    public fun name(
        card: &SuitizenCard,
    ): String{
        let mut name = string::utf8(b"");
        name.append(card.first_name());
        name.append(string::utf8(b" "));
        name.append(card.last_name());
        name
    }
    public entry fun withdraw(
        _cap: &AdminCap,
        treasury: &mut Treasury, 
        ctx: &mut TxContext, 
    ){
        let withdraw_amount = treasury.balance.value();
        let withdraw_balance = treasury.balance.split(withdraw_amount);
        let withdraw_coin = coin::from_balance(withdraw_balance, ctx);
        transfer::public_transfer(withdraw_coin, ctx.sender());
    }

    public(package)fun assert_if_ns_expired_by_card(
        card: &SuitizenCard,
        clock: &Clock,
    ){
        assert!(!dof::borrow<Name, SuinsRegistration >(&card.id, Name{}).has_expired(clock), ENsExpired);
    }

    fun assert_if_face_existed(
        registry: &Registry,
        face_feature: String,
    ){
        assert!(!registry.face_tab.contains(face_feature), EFaceAlreadyUsed);
    }

    fun assert_if_name_existed(
        registry: &Registry,
        sui_ns: &SuinsRegistration,
    ){
        let first_name = *sui_ns.domain().tld();
        let last_name =  *sui_ns.domain().sld();
        
        let mut name = string::utf8(b"");
        name.append( first_name);
        name.append(last_name);

        assert!(!registry.reg_tab.contains(*name.as_bytes()), ENameServiceAlreadyUsed);
    }

    fun assert_if_index_existed(
        registry: &Registry,
        index: u64,
    ){
        assert!(!registry.pfp_tab.contains(index), EPfpAlreadyUsed);
    }

    fun assert_if_ns_expired_by_ns(
        sui_ns: &SuinsRegistration,
        clock: &Clock,
    ){
        assert!(!sui_ns.has_expired(clock), ENsExpired);
    }

    fun assert_if_no_ns(
        card: &SuitizenCard,
    ){
        assert!(dof::exists_(&card.id, Name{}), ENoNsBoound);
    }


    fun assert_if_balance_not_matched(
        treasury: &Treasury, 
        balance: &Balance<SUI>,
    ){
        assert!(treasury.register_fee == balance.value(), EBalanceNotMatched)
    }
    
}
