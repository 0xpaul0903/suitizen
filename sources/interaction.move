module suitizen::interaction{

     use sui::{
          table::{Self, Table},
          dynamic_field as df,
          clock::{Clock},
     };

     use std::{
          string::{Self, String},
     };

     use suitizen::suitizen::{Self, SuitizenCard};
     use suitizen::config::{Self, GlobalConfig};

     const VERSION: u64 = 1;

     // define category 
     const VOTE: u64 = 0;
     const DISCUSS: u64 = 1;

     // define error
     const ECategoryNotDefined: u64 = 0;
     const EVoteOptionLownerThanTwo: u64 = 1;
     const ECategoryNoCorrect: u64 = 2;
     const EAlreadyVoted: u64 = 3;

     public struct DiscussionThread has copy, drop ,store {}
     public struct VoteSituation has copy, drop ,store {}

     public struct VoteStatus has store {
          options: vector<VoteOption>,
          record: Table<ID, u64>,
          user_amount: u64,
     }
     
     public struct Comment has store {
          sender: ID,
          name: String, 
          content: String, 
     }

     public struct VoteOption has store {
          content: String,
          amount: u64,
     } 
     
     public struct InteractionRecord has key {
          id: UID,
          vote_tab: Table<u64, ID>,
          discuss_tab: Table<u64, ID>, 
     }


     public struct Interaction has key {
          id : UID,
          flow_num: u64,
          category: u64,
          category_str: String,
          topic: String,
          description: String,
          host: ID,
          last_update: u64,
     }

     public struct TypeDict has key {
          id: UID,
          dict: Table<u64, String>,
     }

     fun init (ctx: &mut TxContext){

          let interaction_record = InteractionRecord{
               id: object::new(ctx),
               vote_tab: table::new<u64, ID>(ctx),
               discuss_tab: table::new<u64, ID>(ctx),
          };

          let mut dict_tab = table::new<u64, String>(ctx);
          dict_tab.add(VOTE, string::utf8(b"VOTE"));
          dict_tab.add(DISCUSS, string::utf8(b"DISCUSS"));
          let dict = TypeDict{
               id: object::new(ctx),
               dict: dict_tab,
          };

          transfer::share_object(dict);
          transfer::share_object(interaction_record);
     }

     #[allow(lint(share_owned))]
     public entry fun new_interaction(
          config: &mut GlobalConfig,
          interaction_record: &mut InteractionRecord,
          type_dict: &TypeDict,
          card: &SuitizenCard,
          category: u64,
          topic: String,
          description: String,
          init_contents: vector<String>,
          clock: &Clock,
          ctx: &mut TxContext,
     ){          
          let interaction = create_interaction(
               config,
               interaction_record,
               type_dict,
               card,
               category,
               topic,
               description,
               init_contents,
               clock,
               ctx,
          );

          transfer::share_object(interaction);
     }

     public entry fun vote(
          config: &GlobalConfig,
          interaction: &mut Interaction,
          card: &mut SuitizenCard,
          vote_option: u64,
          clock:&Clock,
     ){
          assert_if_category_not_correct(interaction.category, VOTE);
          let vote_status = df::borrow_mut<VoteSituation, VoteStatus>(&mut interaction.id, VoteSituation{});
          assert_if_already_voted(card, vote_status);
          vote_to(config, vote_status, card, vote_option, clock);
          update_last_update_ts(interaction, clock);
     }

     public entry fun discuss(
          config: &GlobalConfig,
          interaction: &mut Interaction,
          card: &mut SuitizenCard,
          content: String, 
          clock: &Clock, 
     ){
          config::assert_if_version_not_matched(config, VERSION);

          assert_if_category_not_correct(interaction.category, DISCUSS);
          let thread = df::borrow_mut<DiscussionThread, vector<Comment>>(&mut interaction.id, DiscussionThread{});
          discuss_to(config, thread, card, content, clock);
          update_last_update_ts(interaction, clock);
     }

     public fun create_interaction (
          config: &mut GlobalConfig,
          interaction_record: &mut InteractionRecord,
          type_dict: &TypeDict,
          card: &SuitizenCard,
          category: u64,
          topic: String,
          description: String,
          init_contents: vector<String>,
          clock: &Clock,
          ctx: &mut TxContext,
     ): Interaction{

          config::assert_if_version_not_matched(config, VERSION);
          assert_if_ns_expired(card, clock);
          assert_if_category_not_defined(category);

          let flow_num = get_flow_num(config, category);

          let mut interaction = Interaction {
               id: object::new(ctx),
               flow_num,
               category,
               category_str: *type_dict.dict.borrow(category),
               topic,
               description,
               host: object::id(card),
               last_update: clock.timestamp_ms(),
          };

          if (category == VOTE){
               attach_vote_options(&mut interaction, init_contents, ctx);
               interaction_record.vote_tab.add(flow_num, interaction.id.to_inner());
               config::add_type_amount(config, VOTE);
          }else{
               attach_discussion_thread(card, &mut interaction, init_contents);
               interaction_record.discuss_tab.add(flow_num, interaction.id.to_inner());
               config::add_type_amount(config, DISCUSS);
          };
          interaction
     }

     fun vote_to(
          config: &GlobalConfig,
          vote_status: &mut VoteStatus,
          card: &SuitizenCard,
          vote_option: u64,
          clock: &Clock,
     ){
          config::assert_if_version_not_matched(config, VERSION);
          assert_if_ns_expired(card, clock);

          let vote_amount = vote_status.options.borrow(vote_option).amount;
          let user_amount = vote_status.user_amount;
          vote_status.options.borrow_mut(vote_option).amount = vote_amount + 1;
          vote_status.user_amount = user_amount + 1;

          vote_status.record.add(object::id(card), 1);
     }

     public fun discuss_to(
          config: &GlobalConfig,
          thread: &mut vector<Comment>,
          card: &mut SuitizenCard,
          content: String,
          clock: &Clock,
          
     ){
          config::assert_if_version_not_matched(config, VERSION);

          assert_if_ns_expired(card, clock);

          thread.push_back(
               Comment{
                    sender: object::id(card),
                    name: card.name(),
                    content,
               }
          );
     }
     public fun add_type(
          config: &GlobalConfig,
          dict: &mut TypeDict,
          key: u64,
          value: String,
     ){
          config::assert_if_version_not_matched(config, VERSION);
          dict.dict.add(key, value);
     }

     fun attach_discussion_thread(
          card: &SuitizenCard,
          interaction: &mut Interaction,
          init_comments: vector<String>,
     ){
          let mut comments = vector::empty<Comment>();
          let mut current_idx = 0;
          while(current_idx < init_comments.length()){
               comments.push_back(
               Comment{
                         sender: object::id(card),
                         name: card.name(),
                         content: *init_comments.borrow(current_idx),
                    }
               );
               current_idx  = current_idx + 1;
          };
          
          df::add(&mut interaction.id, DiscussionThread{}, comments);
     }

     fun attach_vote_options(
          interaction: &mut Interaction,
          vote_options: vector<String>,
          ctx: &mut TxContext,
     ){
          assert_if_vote_options_lower_than_two(vote_options);
          let mut options = vector::empty<VoteOption>();
          let mut current_idx = 0;
          while(current_idx < vote_options.length()){
               options.push_back(
                    VoteOption{
                         content: *vote_options.borrow(current_idx),
                         amount: 0,
                    }
               );
               current_idx = current_idx + 1;
          };
          let state = VoteStatus{
               options,
               user_amount: 0,
               record: table::new<ID, u64>(ctx),
          };

          df::add(&mut interaction.id, VoteSituation{}, state);
     }

     fun get_flow_num(
          config: &GlobalConfig,
          interaction_type: u64,
     ): u64{
          let state_tab = config.interaction_state();
          *state_tab.borrow(interaction_type)
     }

     fun update_last_update_ts(
          interaction: &mut Interaction,
          clock: &Clock,
     ){
          interaction.last_update = clock.timestamp_ms();
     }

     fun assert_if_category_not_defined(category: u64){
          assert!(category == VOTE || category == DISCUSS, ECategoryNotDefined);
     }

     fun assert_if_vote_options_lower_than_two(
         vote_options: vector<String>,
     ){
          assert!(vote_options.length() >= 2, EVoteOptionLownerThanTwo);
     }

     fun assert_if_category_not_correct(
          category: u64,
          target: u64
     ){
          assert!(category == target, ECategoryNoCorrect);
     }

     fun assert_if_already_voted(
          card: &SuitizenCard,
          vote_status: &VoteStatus, 
     ){
          assert!(!vote_status.record.contains(object::id(card)),EAlreadyVoted);
     }

     fun assert_if_ns_expired(
          card: &SuitizenCard,
          clock: &Clock,
     ){
          suitizen::assert_if_ns_expired_by_card(card, clock);
     }

}
