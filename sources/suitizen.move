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
        dynamic_field as df,
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
    const EOverGuardianLimit: u64 = 7;
    const EGuardianEmpty: u64 = 8;
    const EAlreadyConfirmed: u64 = 9;
    const ENotConfiredBefore: u64 = 10;
    const ENotArrivedThreshold: u64 = 11;
    const ECardIdNotMatched: u64 = 12;
    

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
        num: u64,
        last_name: String,
        first_name: String,
        card_img: String, // blob id 
        face_feature: String,  // blob id 
        birth: u64,
        guardians: vector<ID>,
    }

    public struct TransferRequest has key {
        id: UID,
        card_id: ID,
        new_owner: address,
        confirm_threshold: u64,
        current_confirm: u64,
        guardians: vector<ID>,
    }

    public struct TransferRequestRecord has key {
        id: UID,
        requester_to_requests: Table<ID,vector<ID>>,
        guardian_to_requests: Table<ID, vector<ID>>,
    }

    public struct Name has copy, store, drop {}
    public struct TransferPass has store, copy, drop{}
    public struct Confirm has store{}
    
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

        let transfer_request_recrod = TransferRequestRecord{
            id: object::new(ctx),
            requester_to_requests: table::new<ID, vector<ID>>(ctx),
            guardian_to_requests: table::new<ID, vector<ID>>(ctx),
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
            string::utf8(b"https://suitizen.walrus.site"),
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
        transfer::share_object(transfer_request_recrod);
    } 

    public entry fun mint(
        config: &mut GlobalConfig,
        registry: &mut Registry,
        treasury: &mut Treasury,
        sui_ns: SuinsRegistration,
        img_index: u64,
        pfp_img: String, // blob id
        card_img: String, // blob id 
        face_feature: String, // blob id 
        birth: u64,
        coin: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let id_card = create_card(config, registry, treasury,  sui_ns, img_index, pfp_img, card_img, face_feature, birth, coin.into_balance(), clock, ctx);
        transfer::transfer(id_card, ctx.sender())
    }

    #[allow(lint(share_owned))]
    public entry fun new_transfer_request(
        config: &GlobalConfig,
        record: &mut TransferRequestRecord,
        new_owner: address, 
        card: &SuitizenCard,
        ctx: &mut TxContext,
    ){
        let transer_request = create_transfer_request(config, record, new_owner, card, ctx);
        transfer::share_object(transer_request);
    }

    public entry fun cancel_transfer_request(
        config: &GlobalConfig,
        record: &mut TransferRequestRecord,
        request: TransferRequest,
        card: &SuitizenCard,
    ){
        config::assert_if_version_not_matched(config, VERSION);
        assert_if_card_id_not_matched(&request, card);
        delete_transfer_request(record, request, card);
    }

    public entry fun confirm(
        config: &GlobalConfig,
        card: &SuitizenCard,
        request: &mut TransferRequest,
    ){
        config::assert_if_version_not_matched(config, VERSION);
        assert_if_already_confirm(request, card);
        
        request.current_confirm = request.current_confirm + 1;
        df::add<ID, Confirm>(&mut request.id, card.id.to_inner(), Confirm{});
        
    }

    public entry fun cancel_confirm(
        config: &GlobalConfig,
        card: &SuitizenCard,
        request: &mut TransferRequest,
    ){
        config::assert_if_version_not_matched(config, VERSION);
        assert_if_not_confirmed_before(request, card);
        request.current_confirm = request.current_confirm - 1;
        let confirm = df::remove<ID, Confirm>(&mut request.id, card.id.to_inner());
        let Confirm{} = confirm;
    }

    public entry fun transfer_card(
        config: &GlobalConfig,
        record: &mut TransferRequestRecord,
        card: SuitizenCard,
        request: TransferRequest,
    ){
        config::assert_if_version_not_matched(config, VERSION);
        assert_if_confirm_amount_lt_threshold(&request);
        let new_owner = request.new_owner;
        delete_transfer_request(record, request, &card);

        transfer::transfer(card, new_owner);

    }

    public fun create_card(
        config: &mut GlobalConfig,
        registry: &mut Registry,
        treasury: &mut Treasury, 
        sui_ns: SuinsRegistration,
        img_index: u64,
        pfp_img: String, // blob id 
        card_img: String, // blob id 
        face_feature: String, // blob id 
        birth: u64,
        balance: Balance<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) : SuitizenCard{

        config::assert_if_version_not_matched(config, VERSION);

        assert_if_ns_expired_by_ns(&sui_ns, clock);
        assert_if_face_existed(registry, face_feature);
        assert_if_name_existed(registry, &sui_ns);
        assert_if_index_existed(registry, img_index);
        assert_if_balance_not_matched(treasury, &balance);

        let first_name = *sui_ns.domain().sld();
        let last_name =  *sui_ns.domain().tld();
        
        let mut name = string::utf8(b"");
        name.append( first_name);
        name.append(last_name);

        config.add_suitizen_amount();

        let mut card = SuitizenCard{
            id: object::new(ctx),
            num: config.citizen_amount(),
            first_name, 
            last_name,
            card_img,
            face_feature,
            birth,
            guardians: vector::empty<ID>(),
        };

        registry.reg_tab.add(name.into_bytes(), card.id.uid_to_inner());
        registry.face_tab.add(face_feature, card.id.uid_to_inner());
        registry.pfp_tab.add(img_index, pfp_img);
        
        dof::add<Name, SuinsRegistration>(&mut card.id, Name{}, sui_ns);

        treasury.balance.join(balance);
        
        card
    }

    public entry fun add_guardian(
        config: &GlobalConfig,
        card: &mut SuitizenCard,
        guardian: ID,
    ){  
        config::assert_if_version_not_matched(config, VERSION);
        assert_if_over_guardian_limit(config, card.guardians.length() + 1);
        card.guardians.push_back(guardian);
    }

    public entry fun remove_guardian(
        config: &GlobalConfig,
        card: &mut SuitizenCard,
        guardian: ID,
    ){
        config::assert_if_version_not_matched(config, VERSION);

        let mut current_idx = 0;
        while (current_idx < card.guardians.length()){
            if (*card.guardians.borrow(current_idx) == guardian){
                card.guardians.swap_remove(current_idx);
            };
            current_idx = current_idx + 1;
        }
    }

    public fun create_transfer_request(
        config: &GlobalConfig,
        record: &mut TransferRequestRecord,
        new_owner: address, 
        card: &SuitizenCard,
        ctx: &mut TxContext,
    ): TransferRequest{

        config::assert_if_version_not_matched(config, VERSION);
        assert_if_guardian_zero(card);

        let confirm_threshold;
        
        if (card.guardians.length() == 1){
            confirm_threshold = 1;
        }else{
            if (card.guardians.length() % 2 == 1){
                confirm_threshold = (card.guardians.length() / 2) + 1;
            }else{
                confirm_threshold = (card.guardians.length() / 2);
            }   
        };

        let transfer_request = TransferRequest{
            id: object::new(ctx),
            card_id: card.id.to_inner(),
            new_owner,
            confirm_threshold,
            current_confirm: 0,
            guardians: copy_guardian(card),
        };

        let requests = get_user_requests_mut(record, card);
        requests.push_back(transfer_request.id.to_inner());

        store_guardian_request_to_record(record, &transfer_request, card);
        
        transfer_request
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
        card.last_name
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

    // admin function 
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
        let first_name = *sui_ns.domain().sld();
        let last_name =  *sui_ns.domain().tld();
        
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

    fun assert_if_over_guardian_limit(
        config: &GlobalConfig,
        guardian_amount: u64,
    ){
        assert!(config.guardian_limit() > guardian_amount, EOverGuardianLimit);
    }

    fun assert_if_guardian_zero(
        card: &SuitizenCard,
    ){
        assert!(card.guardians.length() != 0 , EGuardianEmpty);
    }

    fun assert_if_already_confirm(
        request: &TransferRequest,
        card:&SuitizenCard,
    ){
        assert!(!df::exists_(&request.id, card.id.to_inner()), EAlreadyConfirmed);
    }

    fun assert_if_not_confirmed_before(
        request: &TransferRequest,
        card:&SuitizenCard,
    ){
        assert!(df::exists_(&request.id, card.id.to_inner()), ENotConfiredBefore);
    }

    fun assert_if_confirm_amount_lt_threshold(
        request: &TransferRequest,
    ){
        assert!(request.current_confirm >= request.confirm_threshold, ENotArrivedThreshold);
    }

    fun assert_if_card_id_not_matched(
        request: &TransferRequest,
        card: &SuitizenCard,
    ){
        assert!(request.card_id.to_bytes() == card.id.to_inner().to_bytes(), ECardIdNotMatched);
    }

    fun copy_guardian(
        card: &SuitizenCard,
    ): vector<ID>{
        let mut copy_vec = vector::empty<ID>();
        let mut current_idx = 0;
        while(current_idx < card.guardians.length()){
            copy_vec.push_back(*card.guardians.borrow(current_idx));
            current_idx = current_idx + 1;
        };
        copy_vec
    }

     fun delete_transfer_request(
        record: &mut TransferRequestRecord,
        request: TransferRequest,
        card: &SuitizenCard,
    ){
        let requests = get_user_requests_mut(record, card);
        
        let mut current_idx = 0;
        while(current_idx < requests.length()){
            if (requests.borrow(current_idx).to_bytes() == request.id.to_bytes()){
                requests.swap_remove(current_idx);
            };
            current_idx = current_idx + 1;
        };

        current_idx = 0;
        while(current_idx < request.guardians.length()){
            let guardian_requests = get_guardian_requests_mut(record, *request.guardians.borrow(current_idx));
            let mut inner_idx = 0;
            while(inner_idx < guardian_requests.length()){
                if (guardian_requests.borrow(inner_idx).to_bytes() == request.id.to_bytes()){
                    guardian_requests.swap_remove(inner_idx);
                };
                inner_idx = inner_idx + 1;
            };
            current_idx = current_idx + 1;
        };

        let TransferRequest{
            id,
            card_id: _,
            new_owner: _,
            confirm_threshold: _,
            current_confirm: _,
            guardians: _,
        } = request;

        object::delete(id);
    }

    fun get_user_requests_mut(
        record: &mut TransferRequestRecord,
        card: &SuitizenCard,
    ): &mut vector<ID>{
        if (record.requester_to_requests.contains(card.id.to_inner())){
            record.requester_to_requests.borrow_mut(card.id.to_inner())
        }else{
            let requests = vector::empty<ID>();
            record.requester_to_requests.add(card.id.to_inner(), requests);
            record.requester_to_requests.borrow_mut(card.id.to_inner())
        }
    }

    fun get_guardian_requests_mut(
        record: &mut TransferRequestRecord,
        guardian: ID,
    ): &mut vector<ID>{
        record.guardian_to_requests.borrow_mut(guardian)
    }

    fun store_guardian_request_to_record(
        record: &mut TransferRequestRecord,
        request: &TransferRequest,
        card: &SuitizenCard,
    ){
        let guardians = card.guardians;

        let mut current_idx = 0;
        while (current_idx < guardians.length()){
            if (record.guardian_to_requests.contains(*guardians.borrow(current_idx))){
                let mut requests = record.guardian_to_requests.remove(*guardians.borrow(current_idx));
                requests.push_back(request.id.to_inner());
                record.guardian_to_requests.add(*guardians.borrow(current_idx), requests);
            }else{
                let mut requests = vector::empty<ID>();
                requests.push_back(request.id.to_inner());
                record.guardian_to_requests.add(*guardians.borrow(current_idx), requests);
            };
            current_idx = current_idx + 1;
        }
    }

    public entry fun take_sui_ns(
        reg: &mut Registry,
        card: &mut SuitizenCard,
        ctx: &mut TxContext,
    ){
        let ns = dof::remove<Name, SuinsRegistration>(&mut card.id, Name{});
        let mut name = string::utf8(b"");
        name.append( card.first_name);
        name.append(card.last_name);
        reg.reg_tab.remove(*name.as_bytes());
        transfer::public_transfer(ns, ctx.sender())
    }    
}
