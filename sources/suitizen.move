module suitizen::suitizen {
    use std::{
        string::{Self, String},
    };
    use sui::{
        table:: {Self, Table,},
        package,
        display,
    };

    use suins::suins_registration::{SuinsRegistration};
    use suitizen::config::{Self, GlobalConfig};

    public struct SUITIZEN has drop{}

    const EDuplicateAssign: u64 = 0;
    const ENameServiceAlreadyUsed: u64 = 1;
    const EFaceAlreadyUsed: u64 = 2;

    const VERSION: u64 = 1;

    public struct Registry has key{
        id: UID,
        reg_tab: Table<vector<u8>, ID>,
        face_lib: Table<String, ID>,
    }
    

    public struct SuitizenCard has key{
        // sui ns need to be dynamic field
        id: UID,
        last_name: String,
        first_name: String,
        card_img: String, // blob id 
        face_feature: String  // blob id 
    }
    
    #[allow(lint(share_owned))]
    fun init (otw: SUITIZEN, ctx: &mut TxContext){
        let registry = Registry{
            id: object::new(ctx),
            reg_tab: table::new<vector<u8>, ID>(ctx),
            face_lib: table::new<String, ID>(ctx),
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
    } 

    public entry fun mint(
        config: &GlobalConfig,
        registry: &mut Registry,
        sui_ns: &SuinsRegistration,
        card_img: String, // blob id 
        face_feature: String, // blob id 
        ctx: &mut TxContext,
    ) {
        let id_card = create_card(config, registry,  sui_ns, card_img, face_feature, ctx);
        transfer::transfer(id_card, ctx.sender())
    }

    public fun create_card(
        config: &GlobalConfig,
        registry: &mut Registry,
        sui_ns: &SuinsRegistration,
        card_img: String, // blob id 
        face_feature: String, // blob id 
        ctx: &mut TxContext,
    ) : SuitizenCard{

        config::assert_if_version_not_matched(config, VERSION);
        assert_if_face_existed(registry, face_feature);
        assert_if_name_existed(registry, sui_ns);

        let first_name = *sui_ns.domain().tld();
        let last_name =  *sui_ns.domain().sld();
        
        let mut name = string::utf8(b"");
        name.append( first_name);
        name.append(last_name);

        let card = SuitizenCard{
            id: object::new(ctx),
            first_name, 
            last_name,
            card_img,
            face_feature,
        };
        registry.reg_tab.add(name.into_bytes(), card.id.uid_to_inner());
        registry.face_lib.add(face_feature, card.id.uid_to_inner());
        card
    }

    public fun rename (
        config: &GlobalConfig,
        registry: &mut Registry,
        sui_ns: &SuinsRegistration,
        card: &mut SuitizenCard,
    ){
        config::assert_if_version_not_matched(config, VERSION);

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

    fun assert_if_face_existed(
        registry: &Registry,
        face_feature: String,
    ){
        assert!(!registry.face_lib.contains(face_feature), EFaceAlreadyUsed);
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
    
}
