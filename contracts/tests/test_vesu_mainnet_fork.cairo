use ghostloop_contracts::authorization::{
    ACTION_BORROW, ACTION_CLOSE_BORROW, ACTION_REPAY, Authorization, hash_authorization,
    hash_borrow_parameters, hash_close_borrow_parameters, hash_repay_parameters,
};
use ghostloop_contracts::ghost_position::{IGhostPositionDispatcher, IGhostPositionDispatcherTrait};
use ghostloop_contracts::interfaces::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::signature::stark_curve::{
    StarkCurveKeyPair, StarkCurveKeyPairImpl, StarkCurveSignerImpl,
};
use snforge_std::signature::{KeyPairTrait, SignerTrait};
use snforge_std::{
    ContractClassTrait, CustomToken, DeclareResultTrait, Token, declare, set_balance,
    start_cheat_caller_address, test_address,
};
use starknet::ContractAddress;

const CAPABILITY_SECRET: felt252 = 0x67686f73746c6f6f705f6d61696e6e65745f666f726b;
const CHAIN_ID: felt252 = 'SN_MAIN';
const DEADLINE: u64 = 1_800_000_000;

const ETH_ADDRESS: felt252 = 0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7;
const USDC_ADDRESS: felt252 = 0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8;
const VESU_PRIME_ADDRESS: felt252 =
    0x0451fe483d5921a2919ddd81d0de6696669bccdacd859f72a4fba7656b97c3b5;
const VESU_MULTIPLY_V2_ADDRESS: felt252 =
    0x07964760e90baa28841ec94714151e03fbc13321797e68a874e88f27c9d58513;
const ERC20_BALANCES_SELECTOR: felt252 =
    0x03a4e8ec16e258a799fe707996fd5d21d42b29adc1499a370edf7f809d8c458a;

const COLLATERAL_AMOUNT: u256 = 20_000_000_000_000_000;
const DEBT_AMOUNT: u256 = 20_000_000;
const PARTIAL_REPAY_AMOUNT: u256 = 5_000_000;
const MAXIMUM_CLOSE_INPUT: u256 = 30_000_000;

fn address(value: felt252) -> ContractAddress {
    value.try_into().unwrap()
}

fn authorization(
    key: StarkCurveKeyPair,
    position: ContractAddress,
    action: felt252,
    parameters_hash: felt252,
    nonce: u64,
) -> Authorization {
    let message_hash = hash_authorization(
        CHAIN_ID, position, action, parameters_hash, nonce, DEADLINE,
    );
    let (signature_r, signature_s) = key.sign(message_hash).unwrap();
    Authorization { nonce, deadline: DEADLINE, signature_r, signature_s }
}

/// This block is immediately before Vesu governance transaction
/// 0x788136...9a9f reduced the Prime ETH/USDC debt cap. It gives us a permanent,
/// real-contract regression test while the live market remains disabled.
#[test]
#[fork("MAINNET_VESU_ACTIVE")]
#[ignore]
fn borrow_repay_and_close_against_real_vesu_prime() {
    let anonymizer = test_address();
    let eth = address(ETH_ADDRESS);
    let usdc = address(USDC_ADDRESS);
    let key = KeyPairTrait::from_secret_key(CAPABILITY_SECRET);
    let contract = declare("GhostPosition").unwrap().contract_class();
    let constructor_calldata = array![
        anonymizer.into(), key.public_key, eth.into(), usdc.into(), VESU_PRIME_ADDRESS,
        VESU_MULTIPLY_V2_ADDRESS,
    ];
    let (position_address, _) = contract.deploy(@constructor_calldata).unwrap();
    let position = IGhostPositionDispatcher { contract_address: position_address };
    let eth_token = IERC20Dispatcher { contract_address: eth };
    let usdc_token = IERC20Dispatcher { contract_address: usdc };

    start_cheat_caller_address(position_address, anonymizer);
    set_balance(position_address, COLLATERAL_AMOUNT, Token::ETH);

    let borrowed = position
        .borrow(
            COLLATERAL_AMOUNT,
            DEBT_AMOUNT,
            DEBT_AMOUNT,
            authorization(
                key,
                position_address,
                ACTION_BORROW,
                hash_borrow_parameters(COLLATERAL_AMOUNT, DEBT_AMOUNT, DEBT_AMOUNT),
                0,
            ),
        );
    assert(borrowed == DEBT_AMOUNT, 'UNEXPECTED_BORROW_AMOUNT');
    assert(usdc_token.balance_of(anonymizer) == borrowed, 'BORROW_NOT_RECEIVED');

    let (after_borrow, collateral_after_borrow, debt_after_borrow) = position.read_position();
    assert(after_borrow.collateral_shares != 0, 'NO_COLLATERAL_SHARES');
    assert(after_borrow.nominal_debt != 0, 'NO_NOMINAL_DEBT');
    assert(collateral_after_borrow != 0, 'NO_COLLATERAL_ASSETS');
    assert(debt_after_borrow >= DEBT_AMOUNT, 'DEBT_TOO_LOW');

    assert(usdc_token.transfer(position_address, PARTIAL_REPAY_AMOUNT), 'REPAY_TRANSFER_FAILED');
    position
        .repay(
            PARTIAL_REPAY_AMOUNT,
            authorization(
                key, position_address, ACTION_REPAY, hash_repay_parameters(PARTIAL_REPAY_AMOUNT), 1,
            ),
        );
    let (_, _, debt_after_repay) = position.read_position();
    assert(debt_after_repay < debt_after_borrow, 'DEBT_DID_NOT_DECREASE');
    assert(debt_after_repay != 0, 'PARTIAL_REPAY_CLOSED_DEBT');

    set_balance(
        anonymizer,
        MAXIMUM_CLOSE_INPUT,
        Token::Custom(
            CustomToken {
                contract_address: usdc, balances_variable_selector: ERC20_BALANCES_SELECTOR,
            },
        ),
    );
    assert(usdc_token.transfer(position_address, MAXIMUM_CLOSE_INPUT), 'CLOSE_TRANSFER_FAILED');
    let (collateral_returned, debt_refund) = position
        .close_borrow(
            MAXIMUM_CLOSE_INPUT,
            authorization(
                key,
                position_address,
                ACTION_CLOSE_BORROW,
                hash_close_borrow_parameters(MAXIMUM_CLOSE_INPUT),
                2,
            ),
        );

    let (closed, collateral_after_close, debt_after_close) = position.read_position();
    assert(closed.collateral_shares == 0, 'COLLATERAL_SHARES_REMAIN');
    assert(closed.nominal_debt == 0, 'NOMINAL_DEBT_REMAINS');
    assert(collateral_after_close == 0, 'COLLATERAL_REMAINS');
    assert(debt_after_close == 0, 'DEBT_REMAINS');
    assert(collateral_returned != 0, 'NO_COLLATERAL_RETURNED');
    assert(debt_refund != 0, 'NO_DEBT_REFUND');
    assert(eth_token.balance_of(anonymizer) == collateral_returned, 'ETH_NOT_RETURNED');
    assert(usdc_token.balance_of(anonymizer) == debt_refund, 'USDC_REFUND_NOT_RETURNED');
    assert(position.next_nonce() == 3, 'NONCE_SEQUENCE_INCORRECT');
}
