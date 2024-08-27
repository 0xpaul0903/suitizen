/// Module: suitizen
module suitizen::suitizen {
    use std::string::{Self, String};
    use sui::{
        table,
        package,
        display,
        bcs,
        coin::{Self, Coin},
        balance::{Balance},
        sui::{SUI},
    };

    use suins::suins_registration::{SuinsRegistration};
    use blob_store::{
        blob,
        system::{System},
        storage_resource::{Storage},
    };

    const RED_STUFF: u8 = 0;

    public struct SUITIZEN has drop{}
    

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
        let registry = table::new<address, ID>(ctx);
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
        
        transfer::public_share_object(registry);
    } 

    public fun mint<CoinType>(
        //system_obj: &mut System<CoinType>,
        //root_hash_vec: vector<u8>, 
        sui_ns: &SuinsRegistration,
        card_img: String, // blob id 
        face_feature: String, // blob id 
        // payment: Coin<CoinType>,
        ctx: &mut TxContext,
    ) {
        let id_card = create_card<CoinType>(sui_ns, card_img, face_feature, ctx);
        transfer::transfer(id_card, ctx.sender())

    }


    public fun create_card<CoinType>(
        //system_obj: &mut System<CoinType>,
        //root_hash_vec: vector<u8>, 
        sui_ns: &SuinsRegistration,
        card_img: String, // blob id 
        face_feature: String, // blob id 
        // payment: Coin<CoinType>,
        ctx: &mut TxContext,
    ) : SuitizenCard{
        let first_name = *sui_ns.domain().sld();
        let last_name = *sui_ns.domain().tld();
        // // get blob id from  walrus
        // let (storage, remain) = store(system_obj, root_hash_vec, payment.into_balance(),ctx);
        SuitizenCard{
            id: object::new(ctx),
            last_name, 
            first_name,
            card_img,
            face_feature,
        }
    }
    
    
}
