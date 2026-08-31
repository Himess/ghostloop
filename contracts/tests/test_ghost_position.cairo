use alexandria_math::i257::I257Trait;
use ghostloop_contracts::authorization::{
    ACTION_BORROW, ACTION_REPAY, Authorization, hash_authorization, hash_repay_parameters,
};
use ghostloop_contracts::ghost_position::{IGhostPositionDispatcher, IGhostPositionDispatcherTrait};
use ghostloop_contracts::interfaces::UpdatePositionResponse;
use snforge_std::signature::stark_curve::{
    StarkCurveKeyPair, StarkCurveKeyPairImpl, StarkCurveSignerImpl,
};
use snforge_std::signature::{KeyPairTrait, SignerTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_block_timestamp,
    start_cheat_caller_address, start_cheat_chain_id, start_mock_call,
};
use starknet::ContractAddress;

const CAPABILITY_SECRET: felt252 = 0x123456789;
const OTHER_SECRET: felt252 = 0x987654321;
const TEST_CHAIN_ID: felt252 = 'SN_GHOST_TEST';
const NOW: u64 = 1_800_000_000;
const DEADLINE: u64 = NOW + 300;

#[derive(Copy, Drop)]
struct Fixture {
    position: ContractAddress,
    anonymizer: ContractAddress,
    usdc: ContractAddress,
    vesu_pool: ContractAddress,
    key: StarkCurveKeyPair,
    dispatcher: IGhostPositionDispatcher,
}

fn address(value: felt252) -> ContractAddress {
    value.try_into().unwrap()
}

fn setup() -> Fixture {
    let anonymizer = address(0x111);
    let eth = address(0x222);
    let usdc = address(0x333);
    let vesu_pool = address(0x444);
    let vesu_multiply = address(0x555);
    let key = KeyPairTrait::from_secret_key(CAPABILITY_SECRET);
    let contract = declare("GhostPosition").unwrap().contract_class();
    let constructor_calldata = array![
        anonymizer.into(), key.public_key, eth.into(), usdc.into(), vesu_pool.into(),
        vesu_multiply.into(),
    ];
    let (position, _) = contract.deploy(@constructor_calldata).unwrap();

    start_cheat_caller_address(position, anonymizer);
    start_cheat_block_timestamp(position, NOW);
    start_cheat_chain_id(position, TEST_CHAIN_ID);

    Fixture {
        position,
        anonymizer,
        usdc,
        vesu_pool,
        key,
        dispatcher: IGhostPositionDispatcher { contract_address: position },
    }
}

fn zero_update_response() -> UpdatePositionResponse {
    UpdatePositionResponse {
        collateral_delta: I257Trait::new(0, false),
        collateral_shares_delta: I257Trait::new(0, false),
        debt_delta: I257Trait::new(0, false),
        nominal_debt_delta: I257Trait::new(0, false),
        bad_debt: 0,
    }
}

fn mock_repay_dependencies(fixture: @Fixture) {
    start_mock_call(*fixture.usdc, selector!("approve"), true);
    start_mock_call(*fixture.vesu_pool, selector!("modify_position"), zero_update_response());
}

fn signed_authorization(
    key: StarkCurveKeyPair,
    action: felt252,
    repay_amount: u256,
    nonce: u64,
    deadline: u64,
    chain_id: felt252,
    position: ContractAddress,
) -> Authorization {
    let hash = hash_authorization(
        chain_id, position, action, hash_repay_parameters(repay_amount), nonce, deadline,
    );
    let (signature_r, signature_s) = key.sign(hash).unwrap();
    Authorization { nonce, deadline, signature_r, signature_s }
}

fn valid_repay_authorization(fixture: @Fixture, repay_amount: u256, nonce: u64) -> Authorization {
    signed_authorization(
        *fixture.key, ACTION_REPAY, repay_amount, nonce, DEADLINE, TEST_CHAIN_ID, *fixture.position,
    )
}

#[test]
fn authorized_repay_consumes_exactly_one_nonce() {
    let fixture = setup();
    mock_repay_dependencies(@fixture);

    fixture.dispatcher.repay(100, valid_repay_authorization(@fixture, 100, 0));

    assert(fixture.dispatcher.next_nonce() == 1, 'NONCE_NOT_CONSUMED');
}

#[test]
#[should_panic(expected: 'UNAUTHORIZED_CALLER')]
fn rejects_unauthorized_caller() {
    let fixture = setup();
    start_cheat_caller_address(fixture.position, address(0x999));

    fixture.dispatcher.repay(100, valid_repay_authorization(@fixture, 100, 0));
}

#[test]
#[should_panic(expected: 'INVALID_NONCE')]
fn rejects_reused_nonce() {
    let fixture = setup();
    mock_repay_dependencies(@fixture);
    let authorization = valid_repay_authorization(@fixture, 100, 0);

    fixture.dispatcher.repay(100, authorization);
    fixture.dispatcher.repay(100, authorization);
}

#[test]
#[should_panic(expected: 'INVALID_NONCE')]
fn rejects_skipped_nonce() {
    let fixture = setup();

    fixture.dispatcher.repay(100, valid_repay_authorization(@fixture, 100, 1));
}

#[test]
#[should_panic(expected: 'AUTH_EXPIRED')]
fn rejects_expired_authorization() {
    let fixture = setup();
    let authorization = signed_authorization(
        fixture.key, ACTION_REPAY, 100, 0, NOW - 1, TEST_CHAIN_ID, fixture.position,
    );

    fixture.dispatcher.repay(100, authorization);
}

#[test]
#[should_panic(expected: 'INVALID_SIGNATURE')]
fn rejects_wrong_chain_id() {
    let fixture = setup();
    let authorization = signed_authorization(
        fixture.key, ACTION_REPAY, 100, 0, DEADLINE, 'SN_WRONG_CHAIN', fixture.position,
    );

    fixture.dispatcher.repay(100, authorization);
}

#[test]
#[should_panic(expected: 'INVALID_SIGNATURE')]
fn rejects_wrong_position_address() {
    let fixture = setup();
    let authorization = signed_authorization(
        fixture.key, ACTION_REPAY, 100, 0, DEADLINE, TEST_CHAIN_ID, address(0x777),
    );

    fixture.dispatcher.repay(100, authorization);
}

#[test]
#[should_panic(expected: 'INVALID_SIGNATURE')]
fn rejects_modified_parameters() {
    let fixture = setup();
    let authorization = valid_repay_authorization(@fixture, 100, 0);

    fixture.dispatcher.repay(101, authorization);
}

#[test]
#[should_panic(expected: 'INVALID_SIGNATURE')]
fn rejects_signature_from_another_key() {
    let fixture = setup();
    let other_key = KeyPairTrait::from_secret_key(OTHER_SECRET);
    let authorization = signed_authorization(
        other_key, ACTION_REPAY, 100, 0, DEADLINE, TEST_CHAIN_ID, fixture.position,
    );

    fixture.dispatcher.repay(100, authorization);
}

#[test]
#[should_panic(expected: 'INVALID_SIGNATURE')]
fn rejects_signature_for_another_action() {
    let fixture = setup();
    let authorization = signed_authorization(
        fixture.key, ACTION_BORROW, 100, 0, DEADLINE, TEST_CHAIN_ID, fixture.position,
    );

    fixture.dispatcher.repay(100, authorization);
}
