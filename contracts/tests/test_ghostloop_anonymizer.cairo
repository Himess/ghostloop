mod test_mocks;
use ghostloop_contracts::authorization::{
    ACTION_CREATE_AND_FUND, Authorization, hash_authorization, hash_create_and_fund_parameters,
};
use ghostloop_contracts::ghost_position::{IGhostPositionDispatcher, IGhostPositionDispatcherTrait};
use ghostloop_contracts::ghostloop_anonymizer::{
    BorrowInput, CloseBorrowInput, CreateAndFundInput, GhostLoopOperation,
    IGhostLoopAnonymizerDispatcher, IGhostLoopAnonymizerDispatcherTrait, IncreaseLeverageInput,
    RepayInput, UnwindInput,
};
use snforge_std::signature::stark_curve::{
    StarkCurveKeyPair, StarkCurveKeyPairImpl, StarkCurveSignerImpl,
};
use snforge_std::signature::{KeyPairTrait, SignerTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_block_timestamp,
    start_cheat_caller_address, start_cheat_chain_id,
};
use starknet::ContractAddress;
use test_mocks::{
    IMockERC20Dispatcher, IMockERC20DispatcherTrait, IMockGhostPositionDispatcher,
    IMockGhostPositionDispatcherTrait,
};

const CAPABILITY_SECRET: felt252 = 0xabc123;
const TEST_CHAIN_ID: felt252 = 'SN_GHOST_TEST';
const POSITION_SALT: felt252 = 0xfeed1234;
const NOW: u64 = 1_800_000_000;
const DEADLINE: u64 = NOW + 300;
const BORROW_NOTE_ID: felt252 = 0xb0;
const COLLATERAL_NOTE_ID: felt252 = 0xc0;
const REFUND_NOTE_ID: felt252 = 0xd0;

#[derive(Copy, Drop)]
struct Fixture {
    pool: ContractAddress,
    eth_address: ContractAddress,
    usdc_address: ContractAddress,
    anonymizer_address: ContractAddress,
    key: StarkCurveKeyPair,
    eth: IMockERC20Dispatcher,
    usdc: IMockERC20Dispatcher,
    anonymizer: IGhostLoopAnonymizerDispatcher,
}

fn address(value: felt252) -> ContractAddress {
    value.try_into().unwrap()
}

fn setup() -> Fixture {
    let pool = address(0x111);
    let vesu_pool = address(0x444);
    let vesu_multiply = address(0x555);
    let token_class = declare("MockERC20").unwrap().contract_class();
    let (eth_address, _) = token_class.deploy(@array![]).unwrap();
    let (usdc_address, _) = token_class.deploy(@array![]).unwrap();
    let position_class = declare("MockGhostPosition").unwrap().contract_class();
    let anonymizer_class = declare("GhostLoopAnonymizer").unwrap().contract_class();
    let constructor_calldata = array![
        pool.into(), (*position_class.class_hash).into(), eth_address.into(), usdc_address.into(),
        vesu_pool.into(), vesu_multiply.into(),
    ];
    let (anonymizer_address, _) = anonymizer_class.deploy(@constructor_calldata).unwrap();
    let key = KeyPairTrait::from_secret_key(CAPABILITY_SECRET);

    start_cheat_caller_address(anonymizer_address, pool);
    start_cheat_block_timestamp(anonymizer_address, NOW);
    start_cheat_chain_id(anonymizer_address, TEST_CHAIN_ID);

    Fixture {
        pool,
        eth_address,
        usdc_address,
        anonymizer_address,
        key,
        eth: IMockERC20Dispatcher { contract_address: eth_address },
        usdc: IMockERC20Dispatcher { contract_address: usdc_address },
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

fn dummy_authorization() -> Authorization {
    Authorization { nonce: 0, deadline: DEADLINE, signature_r: 0, signature_s: 0 }
}

fn create_position(fixture: @Fixture, amount: u256) -> ContractAddress {
    fixture.eth.mint(*fixture.anonymizer_address, amount);
    fixture
        .anonymizer
        .privacy_invoke(
            *fixture.eth_address,
            *fixture.eth_address,
            amount,
            GhostLoopOperation::CreateAndFund(creation_input(fixture, amount)),
        );
    fixture.anonymizer.get_position(*fixture.key.public_key, POSITION_SALT)
}

fn borrow_input(fixture: @Fixture, debt_amount: u256, note_id: felt252) -> BorrowInput {
    BorrowInput {
        capability_public_key: *fixture.key.public_key,
        position_salt: POSITION_SALT,
        debt_amount,
        minimum_borrowed: debt_amount,
        note_id,
        authorization: dummy_authorization(),
    }
}

fn repay_input(fixture: @Fixture) -> RepayInput {
    RepayInput {
        capability_public_key: *fixture.key.public_key,
        position_salt: POSITION_SALT,
        authorization: dummy_authorization(),
    }
}

fn close_input(fixture: @Fixture, refund_note_id: felt252) -> CloseBorrowInput {
    CloseBorrowInput {
        capability_public_key: *fixture.key.public_key,
        position_salt: POSITION_SALT,
        collateral_note_id: COLLATERAL_NOTE_ID,
        debt_refund_note_id: refund_note_id,
        authorization: dummy_authorization(),
    }
}

fn increase_leverage_input(fixture: @Fixture) -> IncreaseLeverageInput {
    IncreaseLeverageInput {
        capability_public_key: *fixture.key.public_key,
        position_salt: POSITION_SALT,
        debt_amount: 20_000_000,
        minimum_lever_collateral: 1,
        authorization: dummy_authorization(),
    }
}

fn unwind_input(fixture: @Fixture) -> UnwindInput {
    UnwindInput {
        capability_public_key: *fixture.key.public_key,
        position_salt: POSITION_SALT,
        maximum_collateral_swap: 10_000_000_000_000_000,
        minimum_collateral_returned: 1,
        collateral_note_id: COLLATERAL_NOTE_ID,
        authorization: dummy_authorization(),
    }
}

#[test]
fn increase_leverage_forwards_exact_margin_and_returns_no_deposit() {
    let fixture = setup();
    let position = create_position(@fixture, 1);
    let add_margin = 20_000_000_000_000_000;
    fixture.eth.mint(fixture.anonymizer_address, add_margin);
    let position_before = fixture.eth.balance_of(position);

    let deposits = fixture
        .anonymizer
        .privacy_invoke(
            fixture.eth_address,
            fixture.eth_address,
            add_margin,
            GhostLoopOperation::IncreaseLeverage(increase_leverage_input(@fixture)),
        );

    assert(deposits.len() == 0, 'EXPECTED_EMPTY_DEPOSITS');
    assert(fixture.eth.balance_of(fixture.anonymizer_address) == 0, 'MARGIN_NOT_FORWARDED');
    assert(fixture.eth.balance_of(position) == position_before + add_margin, 'MARGIN_MISMATCH');
}

#[test]
fn unwind_credits_measured_collateral_to_one_open_note() {
    let fixture = setup();
    let initial_position_balance = 10;
    let settlement_anchor = 1;
    let position = create_position(@fixture, initial_position_balance);
    fixture.eth.mint(fixture.anonymizer_address, settlement_anchor);
    let returned = initial_position_balance + settlement_anchor;
    IMockGhostPositionDispatcher { contract_address: position }
        .configure_close(returned, 0, returned, 0);

    let deposits = fixture
        .anonymizer
        .privacy_invoke(
            fixture.eth_address,
            fixture.eth_address,
            settlement_anchor,
            GhostLoopOperation::Unwind(unwind_input(@fixture)),
        );

    assert(deposits.len() == 1, 'EXPECTED_ONE_DEPOSIT');
    let deposit = *deposits[0];
    assert(deposit.note_id == COLLATERAL_NOTE_ID, 'WRONG_NOTE');
    assert(deposit.token == fixture.eth_address, 'WRONG_TOKEN');
    assert(deposit.amount == returned.try_into().unwrap(), 'WRONG_AMOUNT');
    assert(
        fixture.eth.allowance(fixture.anonymizer_address, fixture.pool) == returned,
        'WRONG_APPROVAL',
    );
}

#[test]
#[should_panic(expected: 'OUTPUT_MISMATCH')]
fn rejects_unwind_return_that_disagrees_with_measured_collateral() {
    let fixture = setup();
    let initial_position_balance = 10;
    let settlement_anchor = 1;
    let position = create_position(@fixture, initial_position_balance);
    fixture.eth.mint(fixture.anonymizer_address, settlement_anchor);
    let transferred = initial_position_balance + settlement_anchor;
    IMockGhostPositionDispatcher { contract_address: position }
        .configure_close(transferred, 0, transferred - 1, 0);

    fixture
        .anonymizer
        .privacy_invoke(
            fixture.eth_address,
            fixture.eth_address,
            settlement_anchor,
            GhostLoopOperation::Unwind(unwind_input(@fixture)),
        );
}

#[test]
fn pool_deploys_and_funds_capability_bound_position() {
    let fixture = setup();
    let amount = 1_000;
    let predicted = fixture.anonymizer.predict_position(fixture.key.public_key, POSITION_SALT);

    let position_address = create_position(@fixture, amount);

    assert(position_address == predicted, 'POSITION_NOT_RECORDED');
    assert(fixture.eth.balance_of(predicted) == amount, 'POSITION_NOT_FUNDED');
    let position = IGhostPositionDispatcher { contract_address: predicted };
    assert(position.anonymizer() == fixture.anonymizer_address, 'WRONG_ANONYMIZER');
    assert(position.capability_public_key() == fixture.key.public_key, 'WRONG_KEY');
    assert(position.next_nonce() == 0, 'WRONG_INITIAL_NONCE');
}

#[test]
fn borrow_credits_measured_usdc_and_approves_only_the_pool() {
    let fixture = setup();
    let position = create_position(@fixture, 1);
    let collateral_amount = 1_000;
    let borrowed_amount = 250;
    let mock_position = IMockGhostPositionDispatcher { contract_address: position };
    mock_position.configure_borrow(borrowed_amount, borrowed_amount);
    fixture.eth.mint(fixture.anonymizer_address, collateral_amount);
    fixture.usdc.mint(position, borrowed_amount);

    let deposits = fixture
        .anonymizer
        .privacy_invoke(
            fixture.eth_address,
            fixture.usdc_address,
            collateral_amount,
            GhostLoopOperation::Borrow(borrow_input(@fixture, borrowed_amount, BORROW_NOTE_ID)),
        );

    assert(deposits.len() == 1, 'WRONG_DEPOSIT_COUNT');
    let deposit = *deposits.at(0);
    assert(deposit.note_id == BORROW_NOTE_ID, 'WRONG_NOTE');
    assert(deposit.token == fixture.usdc_address, 'WRONG_TOKEN');
    let borrowed_note_amount: u128 = borrowed_amount.try_into().unwrap();
    assert(deposit.amount == borrowed_note_amount, 'WRONG_AMOUNT');
    assert(
        fixture.usdc.allowance(fixture.anonymizer_address, fixture.pool) == borrowed_amount,
        'WRONG_ALLOWANCE',
    );
}

#[test]
fn repay_forwards_exact_usdc_and_returns_no_deposit() {
    let fixture = setup();
    let position = create_position(@fixture, 1);
    let repay_amount = 100;
    fixture.usdc.mint(fixture.anonymizer_address, repay_amount);

    let deposits = fixture
        .anonymizer
        .privacy_invoke(
            fixture.usdc_address,
            fixture.usdc_address,
            repay_amount,
            GhostLoopOperation::Repay(repay_input(@fixture)),
        );

    assert(deposits.is_empty(), 'EXPECTED_NO_DEPOSIT');
    assert(fixture.usdc.balance_of(fixture.anonymizer_address) == 0, 'INPUT_NOT_FORWARDED');
    assert(fixture.usdc.balance_of(position) == repay_amount, 'POSITION_NOT_FUNDED');
    assert(
        IMockGhostPositionDispatcher { contract_address: position }.last_repay() == repay_amount,
        'REPAY_NOT_CALLED',
    );
}

#[test]
fn close_credits_collateral_and_optional_refund_to_distinct_notes() {
    let fixture = setup();
    let position = create_position(@fixture, 1);
    let maximum_debt_input = 100;
    let collateral_returned = 900;
    let debt_refund = 25;
    let mock_position = IMockGhostPositionDispatcher { contract_address: position };
    mock_position
        .configure_close(collateral_returned, debt_refund, collateral_returned, debt_refund);
    fixture.usdc.mint(fixture.anonymizer_address, maximum_debt_input);
    fixture.eth.mint(position, collateral_returned);
    fixture.usdc.mint(position, debt_refund);

    let deposits = fixture
        .anonymizer
        .privacy_invoke(
            fixture.usdc_address,
            fixture.eth_address,
            maximum_debt_input,
            GhostLoopOperation::CloseBorrow(close_input(@fixture, REFUND_NOTE_ID)),
        );

    assert(deposits.len() == 2, 'WRONG_DEPOSIT_COUNT');
    let collateral = *deposits.at(0);
    let refund = *deposits.at(1);
    assert(collateral.note_id == COLLATERAL_NOTE_ID, 'WRONG_COLLATERAL_NOTE');
    assert(collateral.token == fixture.eth_address, 'WRONG_COLLATERAL_TOKEN');
    let collateral_note_amount: u128 = collateral_returned.try_into().unwrap();
    assert(collateral.amount == collateral_note_amount, 'WRONG_COLLATERAL_AMOUNT');
    assert(refund.note_id == REFUND_NOTE_ID, 'WRONG_REFUND_NOTE');
    assert(refund.token == fixture.usdc_address, 'WRONG_REFUND_TOKEN');
    let refund_note_amount: u128 = debt_refund.try_into().unwrap();
    assert(refund.amount == refund_note_amount, 'WRONG_REFUND_AMOUNT');
    assert(
        fixture.eth.allowance(fixture.anonymizer_address, fixture.pool) == collateral_returned,
        'WRONG_ETH_ALLOWANCE',
    );
    assert(
        fixture.usdc.allowance(fixture.anonymizer_address, fixture.pool) == debt_refund,
        'WRONG_USDC_ALLOWANCE',
    );
}

#[test]
fn close_without_refund_uses_only_the_collateral_note() {
    let fixture = setup();
    let position = create_position(@fixture, 1);
    let maximum_debt_input = 100;
    let collateral_returned = 900;
    let mock_position = IMockGhostPositionDispatcher { contract_address: position };
    mock_position.configure_close(collateral_returned, 0, collateral_returned, 0);
    fixture.usdc.mint(fixture.anonymizer_address, maximum_debt_input);
    fixture.eth.mint(position, collateral_returned);

    let deposits = fixture
        .anonymizer
        .privacy_invoke(
            fixture.usdc_address,
            fixture.eth_address,
            maximum_debt_input,
            GhostLoopOperation::CloseBorrow(close_input(@fixture, 0)),
        );

    assert(deposits.len() == 1, 'WRONG_DEPOSIT_COUNT');
    assert((*deposits.at(0)).note_id == COLLATERAL_NOTE_ID, 'WRONG_NOTE');
}

#[test]
#[should_panic(expected: 'UNAUTHORIZED_CALLER')]
fn rejects_non_pool_caller() {
    let fixture = setup();
    start_cheat_caller_address(fixture.anonymizer_address, address(0x999));

    fixture
        .anonymizer
        .privacy_invoke(
            fixture.eth_address,
            fixture.eth_address,
            1_000,
            GhostLoopOperation::CreateAndFund(creation_input(@fixture, 1_000)),
        );
}

#[test]
#[should_panic(expected: 'INVALID_SIGNATURE')]
fn rejects_funding_amount_modified_after_signing() {
    let fixture = setup();
    let authorization_for_1_000 = creation_input(@fixture, 1_000);

    fixture
        .anonymizer
        .privacy_invoke(
            fixture.eth_address,
            fixture.eth_address,
            1_001,
            GhostLoopOperation::CreateAndFund(authorization_for_1_000),
        );
}

#[test]
#[should_panic(expected: 'POSITION_EXISTS')]
fn rejects_redeployment_for_same_key_and_salt() {
    let fixture = setup();
    let amount = 1_000;
    let input = creation_input(@fixture, amount);
    fixture.eth.mint(fixture.anonymizer_address, amount);

    fixture
        .anonymizer
        .privacy_invoke(
            fixture.eth_address,
            fixture.eth_address,
            amount,
            GhostLoopOperation::CreateAndFund(input),
        );
    fixture
        .anonymizer
        .privacy_invoke(
            fixture.eth_address,
            fixture.eth_address,
            amount,
            GhostLoopOperation::CreateAndFund(input),
        );
}

#[test]
#[should_panic(expected: 'POSITION_NOT_FOUND')]
fn rejects_lifecycle_action_for_unknown_position() {
    let fixture = setup();

    fixture
        .anonymizer
        .privacy_invoke(
            fixture.eth_address,
            fixture.usdc_address,
            1,
            GhostLoopOperation::Borrow(borrow_input(@fixture, 1, BORROW_NOTE_ID)),
        );
}

#[test]
#[should_panic(expected: 'OUTPUT_MISMATCH')]
fn rejects_position_return_that_disagrees_with_measured_borrow() {
    let fixture = setup();
    let position = create_position(@fixture, 1);
    let mock_position = IMockGhostPositionDispatcher { contract_address: position };
    mock_position.configure_borrow(250, 249);
    fixture.eth.mint(fixture.anonymizer_address, 1_000);
    fixture.usdc.mint(position, 250);

    fixture
        .anonymizer
        .privacy_invoke(
            fixture.eth_address,
            fixture.usdc_address,
            1_000,
            GhostLoopOperation::Borrow(borrow_input(@fixture, 250, BORROW_NOTE_ID)),
        );
}

#[test]
#[should_panic(expected: 'ZERO_OUT_AMOUNT')]
fn rejects_zero_borrow_output() {
    let fixture = setup();
    let position = create_position(@fixture, 1);
    IMockGhostPositionDispatcher { contract_address: position }.configure_borrow(0, 0);
    fixture.eth.mint(fixture.anonymizer_address, 1_000);

    fixture
        .anonymizer
        .privacy_invoke(
            fixture.eth_address,
            fixture.usdc_address,
            1_000,
            GhostLoopOperation::Borrow(borrow_input(@fixture, 250, BORROW_NOTE_ID)),
        );
}

#[test]
#[should_panic(expected: 'OUTPUT_OVERFLOW')]
fn rejects_borrow_output_that_does_not_fit_open_note() {
    let fixture = setup();
    let position = create_position(@fixture, 1);
    let overflow: u256 = 0x100000000000000000000000000000000;
    IMockGhostPositionDispatcher { contract_address: position }
        .configure_borrow(overflow, overflow);
    fixture.eth.mint(fixture.anonymizer_address, 1_000);
    fixture.usdc.mint(position, overflow);

    fixture
        .anonymizer
        .privacy_invoke(
            fixture.eth_address,
            fixture.usdc_address,
            1_000,
            GhostLoopOperation::Borrow(borrow_input(@fixture, 250, BORROW_NOTE_ID)),
        );
}

#[test]
#[should_panic(expected: 'NOTE_ID_REQUIRED')]
fn close_refund_requires_a_second_open_note() {
    let fixture = setup();
    let position = create_position(@fixture, 1);
    IMockGhostPositionDispatcher { contract_address: position }.configure_close(900, 25, 900, 25);
    fixture.usdc.mint(fixture.anonymizer_address, 100);
    fixture.eth.mint(position, 900);
    fixture.usdc.mint(position, 25);

    fixture
        .anonymizer
        .privacy_invoke(
            fixture.usdc_address,
            fixture.eth_address,
            100,
            GhostLoopOperation::CloseBorrow(close_input(@fixture, 0)),
        );
}

#[test]
#[should_panic(expected: 'UNEXPECTED_NOTE_ID')]
fn close_without_refund_rejects_an_unused_open_note() {
    let fixture = setup();
    let position = create_position(@fixture, 1);
    IMockGhostPositionDispatcher { contract_address: position }.configure_close(900, 0, 900, 0);
    fixture.usdc.mint(fixture.anonymizer_address, 100);
    fixture.eth.mint(position, 900);

    fixture
        .anonymizer
        .privacy_invoke(
            fixture.usdc_address,
            fixture.eth_address,
            100,
            GhostLoopOperation::CloseBorrow(close_input(@fixture, REFUND_NOTE_ID)),
        );
}
