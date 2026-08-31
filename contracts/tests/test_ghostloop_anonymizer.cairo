use ghostloop_contracts::authorization::{
    ACTION_CREATE_AND_FUND, Authorization, hash_authorization, hash_create_and_fund_parameters,
};
use ghostloop_contracts::ghost_position::{IGhostPositionDispatcher, IGhostPositionDispatcherTrait};
use ghostloop_contracts::ghostloop_anonymizer::{
    CreateAndFundInput, IGhostLoopAnonymizerDispatcher, IGhostLoopAnonymizerDispatcherTrait,
};
use snforge_std::signature::stark_curve::{
    StarkCurveKeyPair, StarkCurveKeyPairImpl, StarkCurveSignerImpl,
};
use snforge_std::signature::{KeyPairTrait, SignerTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_block_timestamp,
    start_cheat_caller_address, start_cheat_chain_id, start_mock_call,
};
use starknet::ContractAddress;

const CAPABILITY_SECRET: felt252 = 0xabc123;
const TEST_CHAIN_ID: felt252 = 'SN_GHOST_TEST';
const POSITION_SALT: felt252 = 0xfeed1234;
const NOW: u64 = 1_800_000_000;
const DEADLINE: u64 = NOW + 300;

#[derive(Copy, Drop)]
struct Fixture {
    pool: ContractAddress,
    eth: ContractAddress,
    anonymizer_address: ContractAddress,
    key: StarkCurveKeyPair,
    anonymizer: IGhostLoopAnonymizerDispatcher,
}

fn address(value: felt252) -> ContractAddress {
    value.try_into().unwrap()
}

fn setup() -> Fixture {
    let pool = address(0x111);
    let eth = address(0x222);
    let usdc = address(0x333);
    let vesu_pool = address(0x444);
    let vesu_multiply = address(0x555);
    let position_class = declare("GhostPosition").unwrap().contract_class();
    let anonymizer_class = declare("GhostLoopAnonymizer").unwrap().contract_class();
    let constructor_calldata = array![
        pool.into(), (*position_class.class_hash).into(), eth.into(), usdc.into(), vesu_pool.into(),
        vesu_multiply.into(),
    ];
    let (anonymizer_address, _) = anonymizer_class.deploy(@constructor_calldata).unwrap();
    let key = KeyPairTrait::from_secret_key(CAPABILITY_SECRET);

    start_cheat_caller_address(anonymizer_address, pool);
    start_cheat_block_timestamp(anonymizer_address, NOW);
    start_cheat_chain_id(anonymizer_address, TEST_CHAIN_ID);

    Fixture {
        pool,
        eth,
        anonymizer_address,
        key,
        anonymizer: IGhostLoopAnonymizerDispatcher { contract_address: anonymizer_address },
    }
}

fn creation_input(fixture: @Fixture, amount: u256) -> CreateAndFundInput {
    let position = fixture.anonymizer.predict_position(*fixture.key.public_key, POSITION_SALT);
    let message_hash = hash_authorization(
        TEST_CHAIN_ID,
        position,
        ACTION_CREATE_AND_FUND,
        hash_create_and_fund_parameters(amount, *fixture.key.public_key, POSITION_SALT),
        0,
        DEADLINE,
    );
    let (signature_r, signature_s) = fixture.key.sign(message_hash).unwrap();
    CreateAndFundInput {
        capability_public_key: *fixture.key.public_key,
        position_salt: POSITION_SALT,
        authorization: Authorization { nonce: 0, deadline: DEADLINE, signature_r, signature_s },
    }
}

fn mock_funding(fixture: @Fixture, balance: u256) {
    start_mock_call(*fixture.eth, selector!("balance_of"), balance);
    start_mock_call(*fixture.eth, selector!("transfer"), true);
}

#[test]
fn pool_deploys_and_funds_capability_bound_position() {
    let fixture = setup();
    let amount = 1_000;
    let predicted = fixture.anonymizer.predict_position(fixture.key.public_key, POSITION_SALT);
    mock_funding(@fixture, amount);

    let deposits = fixture
        .anonymizer
        .privacy_invoke(fixture.eth, fixture.eth, amount, creation_input(@fixture, amount));

    assert(deposits.is_empty(), 'EXPECTED_NO_DEPOSIT');
    assert(
        fixture.anonymizer.get_position(fixture.key.public_key, POSITION_SALT) == predicted,
        'POSITION_NOT_RECORDED',
    );
    let position = IGhostPositionDispatcher { contract_address: predicted };
    assert(position.anonymizer() == fixture.anonymizer_address, 'WRONG_ANONYMIZER');
    assert(position.capability_public_key() == fixture.key.public_key, 'WRONG_KEY');
    assert(position.next_nonce() == 0, 'WRONG_INITIAL_NONCE');
}

#[test]
#[should_panic(expected: 'UNAUTHORIZED_CALLER')]
fn rejects_non_pool_caller() {
    let fixture = setup();
    start_cheat_caller_address(fixture.anonymizer_address, address(0x999));

    fixture
        .anonymizer
        .privacy_invoke(fixture.eth, fixture.eth, 1_000, creation_input(@fixture, 1_000));
}

#[test]
#[should_panic(expected: 'INVALID_SIGNATURE')]
fn rejects_funding_amount_modified_after_signing() {
    let fixture = setup();
    let authorization_for_1_000 = creation_input(@fixture, 1_000);

    fixture.anonymizer.privacy_invoke(fixture.eth, fixture.eth, 1_001, authorization_for_1_000);
}

#[test]
#[should_panic(expected: 'POSITION_EXISTS')]
fn rejects_redeployment_for_same_key_and_salt() {
    let fixture = setup();
    let amount = 1_000;
    let input = creation_input(@fixture, amount);
    mock_funding(@fixture, amount);

    fixture.anonymizer.privacy_invoke(fixture.eth, fixture.eth, amount, input);
    fixture.anonymizer.privacy_invoke(fixture.eth, fixture.eth, amount, input);
}
