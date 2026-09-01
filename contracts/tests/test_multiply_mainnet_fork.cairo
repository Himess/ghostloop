use ghostloop_contracts::authorization::{
    ACTION_INCREASE_LEVERAGE, ACTION_UNWIND, Authorization, hash_authorization,
    hash_increase_leverage_parameters, hash_unwind_parameters,
};
use ghostloop_contracts::ghost_position::{IGhostPositionDispatcher, IGhostPositionDispatcherTrait};
use ghostloop_contracts::interfaces::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::signature::stark_curve::{
    StarkCurveKeyPair, StarkCurveKeyPairImpl, StarkCurveSignerImpl,
};
use snforge_std::signature::{KeyPairTrait, SignerTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, Token, declare, set_balance, start_cheat_caller_address,
    test_address,
};
use starknet::ContractAddress;

const CAPABILITY_SECRET: felt252 = 0x6d756c7469706c795f6d61696e6e65745f666f726b;
const CHAIN_ID: felt252 = 'SN_MAIN';
const DEADLINE: u64 = 1_800_000_000;

const ETH_ADDRESS: felt252 = 0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7;
const USDC_ADDRESS: felt252 = 0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8;
const VESU_PRIME_ADDRESS: felt252 =
    0x0451fe483d5921a2919ddd81d0de6696669bccdacd859f72a4fba7656b97c3b5;
const VESU_MULTIPLY_V2_ADDRESS: felt252 =
    0x07964760e90baa28841ec94714151e03fbc13321797e68a874e88f27c9d58513;

const ADD_MARGIN: u256 = 20_000_000_000_000_000;
const DEBT_AMOUNT: u128 = 20_000_000;
const MINIMUM_LEVER_COLLATERAL: u128 = 1;
const MAXIMUM_COLLATERAL_SWAP: u128 = 10_000_000_000_000_000;
const MINIMUM_COLLATERAL_RETURNED: u256 = 1;

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

/// Uses canonical Vesu Prime, Multiply V2, Ekubo, ETH, and USDC contracts at
/// the last block before the live ETH/USDC debt cap was disabled.
#[test]
#[fork("MAINNET_VESU_ACTIVE")]
#[ignore]
fn increase_leverage_and_full_unwind_against_real_mainnet_contracts() {
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

    start_cheat_caller_address(position_address, anonymizer);
    set_balance(position_address, ADD_MARGIN, Token::ETH);

    let (collateral_added, debt_added) = position
        .increase_leverage(
            ADD_MARGIN,
            DEBT_AMOUNT,
            MINIMUM_LEVER_COLLATERAL,
            authorization(
                key,
                position_address,
                ACTION_INCREASE_LEVERAGE,
                hash_increase_leverage_parameters(
                    ADD_MARGIN, DEBT_AMOUNT, MINIMUM_LEVER_COLLATERAL,
                ),
                0,
            ),
        );
    assert(collateral_added > ADD_MARGIN, 'LEVER_COLLATERAL_MISSING');
    assert(debt_added >= DEBT_AMOUNT.into(), 'LEVER_DEBT_MISSING');
    let (levered, collateral_before_unwind, debt_before_unwind) = position.read_position();
    assert(levered.collateral_shares != 0, 'NO_LEVER_COLLATERAL');
    assert(levered.nominal_debt != 0, 'NO_LEVER_DEBT');
    assert(collateral_before_unwind != 0, 'NO_COLLATERAL_ASSETS');
    assert(debt_before_unwind != 0, 'NO_DEBT_ASSETS');

    let collateral_returned = position
        .unwind(
            MAXIMUM_COLLATERAL_SWAP,
            MINIMUM_COLLATERAL_RETURNED,
            authorization(
                key,
                position_address,
                ACTION_UNWIND,
                hash_unwind_parameters(MAXIMUM_COLLATERAL_SWAP, MINIMUM_COLLATERAL_RETURNED),
                1,
            ),
        );
    let (closed, collateral_after, debt_after) = position.read_position();
    assert(closed.collateral_shares == 0, 'COLLATERAL_SHARES_REMAIN');
    assert(closed.nominal_debt == 0, 'NOMINAL_DEBT_REMAINS');
    assert(collateral_after == 0, 'COLLATERAL_REMAINS');
    assert(debt_after == 0, 'DEBT_REMAINS');
    assert(collateral_returned != 0, 'NO_COLLATERAL_RETURNED');
    assert(eth_token.balance_of(anonymizer) == collateral_returned, 'ETH_NOT_RETURNED');
    assert(position.next_nonce() == 2, 'NONCE_SEQUENCE_INCORRECT');
}
