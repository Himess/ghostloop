use core::hash::HashStateTrait;
use core::poseidon::PoseidonTrait;
use starknet::ContractAddress;

pub const AUTH_DOMAIN: felt252 = 'GHOSTLOOP_AUTH';
pub const AUTH_VERSION: felt252 = 1;

pub const ACTION_CREATE_AND_FUND: felt252 = 0;
pub const ACTION_BORROW: felt252 = 1;
pub const ACTION_REPAY: felt252 = 2;
pub const ACTION_CLOSE_BORROW: felt252 = 3;
pub const ACTION_INCREASE_LEVERAGE: felt252 = 4;
pub const ACTION_UNWIND: felt252 = 5;

#[derive(Serde, Copy, Drop, PartialEq, Debug)]
pub struct Authorization {
    pub nonce: u64,
    pub deadline: u64,
    pub signature_r: felt252,
    pub signature_s: felt252,
}

pub fn hash_authorization(
    chain_id: felt252,
    position: ContractAddress,
    action: felt252,
    parameters_hash: felt252,
    nonce: u64,
    deadline: u64,
) -> felt252 {
    PoseidonTrait::new()
        .update(AUTH_DOMAIN)
        .update(AUTH_VERSION)
        .update(chain_id)
        .update(position.into())
        .update(action)
        .update(parameters_hash)
        .update(nonce.into())
        .update(deadline.into())
        .finalize()
}

pub fn hash_borrow_parameters(
    collateral_amount: u256, debt_amount: u256, minimum_borrowed: u256,
) -> felt252 {
    PoseidonTrait::new()
        .update(collateral_amount.low.into())
        .update(collateral_amount.high.into())
        .update(debt_amount.low.into())
        .update(debt_amount.high.into())
        .update(minimum_borrowed.low.into())
        .update(minimum_borrowed.high.into())
        .finalize()
}

pub fn hash_create_and_fund_parameters(
    amount: u256, capability_public_key: felt252, position_salt: felt252,
) -> felt252 {
    PoseidonTrait::new()
        .update(amount.low.into())
        .update(amount.high.into())
        .update(capability_public_key)
        .update(position_salt)
        .finalize()
}

pub fn hash_repay_parameters(repay_amount: u256) -> felt252 {
    PoseidonTrait::new().update(repay_amount.low.into()).update(repay_amount.high.into()).finalize()
}

pub fn hash_close_borrow_parameters(maximum_debt_input: u256) -> felt252 {
    PoseidonTrait::new()
        .update(maximum_debt_input.low.into())
        .update(maximum_debt_input.high.into())
        .finalize()
}
