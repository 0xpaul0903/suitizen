module suitizen::proposal{

     use sui::{
          table::{Self, Table},
          package::{Self},
          display::{Self,},
          dynamic_field as df,
     };

     use std::{
          string::{Self, String},
     };

     use suitizen::suitizen::{SuitizenCard};
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

     public struct PROPOSAL has drop{}

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

     public struct Proposal has key {
          id : UID,
          category: u64,
          category_str: String,
          topic: String,
          description: String,
          blob_id: String,
          proposer: ID,
     }

     public struct TypeDict has key {
          id: UID,
          dict: Table<u64, String>,
     }

     fun init (otw: PROPOSAL, ctx: &mut TxContext){

          // setup Kapy display
          let keys = vector[
               string::utf8(b"name"),
               string::utf8(b"description"),
               string::utf8(b"image_url"),
          ];

          let values = vector[
               // topic
               string::utf8(b"[{category_str}] - {topic}"),
               // description
               string::utf8(b"{content}"),
               // image_url
               string::utf8(b"https://aggregator-devnet.walrus.space/v1/{blob_id}"),
          ];

          let deployer = ctx.sender();
          let publisher = package::claim(otw, ctx);
          let mut displayer = display::new_with_fields<Proposal>(
               &publisher, keys, values, ctx,
          );
          display::update_version(&mut displayer);

          transfer::public_transfer(displayer, deployer);
          transfer::public_transfer(publisher, deployer);
          
          let mut dict_tab = table::new<u64, String>(ctx);
          dict_tab.add(VOTE, string::utf8(b"VOTE"));
          dict_tab.add(DISCUSS, string::utf8(b"DISCUSS"));
          let dict = TypeDict{
               id: object::new(ctx),
               dict: dict_tab,
          };

          transfer::transfer(dict, ctx.sender());
     }

     #[allow(lint(share_owned))]
     public entry fun new_proposal(
          config: &GlobalConfig,
          type_dict: &TypeDict,
          card: &SuitizenCard,
          category: u64,
          topic: String,
          description: String,
          blob_id: String,
          init_contents: vector<String>,
          ctx: &mut TxContext,
     ){          
          let proposal = create_proposal(
               config,
               type_dict,
               card,
               category,
               topic,
               description,
               blob_id,
               init_contents,
               ctx,
          );

          transfer::share_object(proposal);
     }

     public entry fun vote(
          config: &GlobalConfig,
          proposal: &mut Proposal,
          card: &mut SuitizenCard,
          vote_option: u64,
     ){
          assert_if_category_not_correct(proposal.category, VOTE);
          let vote_status = df::borrow_mut<VoteSituation, VoteStatus>(&mut proposal.id, VoteSituation{});
          assert_if_already_voted(card, vote_status);
          vote_to(config, vote_status, card, vote_option);
     }

     public entry fun discuss(
          config: &GlobalConfig,
          proposal: &mut Proposal,
          card: &mut SuitizenCard,
          content: String, 
     ){
          config::assert_if_version_not_matched(config, VERSION);

          assert_if_category_not_correct(proposal.category, DISCUSS);
          let thread = df::borrow_mut<DiscussionThread, vector<Comment>>(&mut proposal.id, DiscussionThread{});
          discuss_to(config, thread, card, content);
     }

     public fun create_proposal (
          config: &GlobalConfig,
          type_dict: &TypeDict,
          card: &SuitizenCard,
          category: u64,
          topic: String,
          description: String,
          blob_id: String,
          init_contents: vector<String>,
          ctx: &mut TxContext,
     ): Proposal{

          config::assert_if_version_not_matched(config, VERSION);

          assert_if_category_not_defined(category);

          let mut proposal = Proposal {
               id: object::new(ctx),
               category,
               category_str: *type_dict.dict.borrow(category),
               topic,
               description,
               blob_id,
               proposer: object::id(card),
          };

          if (category == VOTE){
               attach_vote_options(&mut proposal, init_contents, ctx);
          }else{
               attach_discussion_thread(card, &mut proposal, init_contents);
          };
          proposal
     }

     public fun vote_to(
          config: &GlobalConfig,
          vote_status: &mut VoteStatus,
          card: &mut SuitizenCard,
          vote_option: u64,
     ){

          config::assert_if_version_not_matched(config, VERSION);

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
     ){
          config::assert_if_version_not_matched(config, VERSION);

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
          proposal: &mut Proposal,
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
          
          df::add(&mut proposal.id, DiscussionThread{}, comments);
     }

     fun attach_vote_options(
          proposal: &mut Proposal,
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

          df::add(&mut proposal.id, VoteSituation{}, state);
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

}
