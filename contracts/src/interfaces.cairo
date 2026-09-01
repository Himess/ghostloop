use alexandria_math::i257::i257;
use starknet::ContractAddress;

/// ABI-compatible with `privacy::objects::OpenNoteDeposit`.
#[derive(Serde, Copy, Drop, PartialEq, Debug)]
pub struct OpenNoteDeposit {
    pub note_id: felt252,
    pub token: ContractAddress,
    pub amount: u128,
}

#[derive(PartialEq, Copy, Drop, Serde)]
pub struct Position {
    pub collateral_shares: u256,
    pub nominal_debt: u256,
}

#[derive(PartialEq, Copy, Drop, Serde, Default)]
pub enum AmountDenomination {
    #[default]
    Native,
    Assets,
}

#[derive(PartialEq, Copy, Drop, Serde, Default)]
pub struct Amount {
    pub denomination: AmountDenomination,
    pub value: i257,
}

#[derive(PartialEq, Copy, Drop, Serde)]
pub struct ModifyPositionParams {
    pub collateral_asset: ContractAddress,
    pub debt_asset: ContractAddress,
    pub user: ContractAddress,
    pub collateral: Amount,
    pub debt: Amount,
}

#[derive(PartialEq, Copy, Drop, Serde)]
pub struct UpdatePositionResponse {
    pub collateral_delta: i257,
    pub collateral_shares_delta: i257,
    pub debt_delta: i257,
    pub nominal_debt_delta: i257,
    pub bad_debt: u256,
}

/// ABI-compatible with Ekubo's `i129`.
#[derive(Serde, Copy, Drop)]
pub struct SignedI129 {
    pub mag: u128,
    pub sign: bool,
}

/// ABI-compatible with Ekubo's `PoolKey`.
#[derive(Serde, Copy, Drop)]
pub struct EkuboPoolKey {
    pub token0: ContractAddress,
    pub token1: ContractAddress,
    pub fee: u128,
    pub tick_spacing: u128,
    pub extension: ContractAddress,
}

#[derive(Serde, Copy, Drop)]
pub struct RouteNode {
    pub pool_key: EkuboPoolKey,
    pub sqrt_ratio_limit: u256,
    pub skip_ahead: u128,
}

#[derive(Serde, Copy, Drop)]
pub struct TokenAmount {
    pub token: ContractAddress,
    pub amount: SignedI129,
}

#[derive(Serde, Drop, Clone)]
pub struct Swap {
    pub route: Array<RouteNode>,
    pub token_amount: TokenAmount,
}

#[derive(Serde, Drop, Clone)]
pub struct IncreaseLeverParams {
    pub pool: ContractAddress,
    pub collateral_asset: ContractAddress,
    pub debt_asset: ContractAddress,
    pub user: ContractAddress,
    pub add_margin: u128,
    pub margin_swap: Array<Swap>,
    pub margin_swap_limit_amount: u128,
    pub lever_swap: Array<Swap>,
    pub lever_swap_limit_amount: u128,
}

#[derive(Serde, Drop, Clone)]
pub struct DecreaseLeverParams {
    pub pool: ContractAddress,
    pub collateral_asset: ContractAddress,
    pub debt_asset: ContractAddress,
    pub user: ContractAddress,
    pub sub_margin: u128,
    pub recipient: ContractAddress,
    pub lever_swap: Array<Swap>,
    pub lever_swap_limit_amount: u128,
    pub lever_swap_weights: Array<u128>,
    pub withdraw_swap: Array<Swap>,
    pub withdraw_swap_limit_amount: u128,
    pub withdraw_swap_weights: Array<u128>,
    pub close_position: bool,
}

#[derive(Serde, Drop, Clone)]
pub enum ModifyLeverAction {
    IncreaseLever: IncreaseLeverParams,
    DecreaseLever: DecreaseLeverParams,
}

#[derive(Serde, Drop, Clone)]
pub struct ModifyLeverParams {
    pub action: ModifyLeverAction,
}

#[derive(Serde, Drop, Clone)]
pub struct ModifyLeverResponse {
    pub collateral_delta: i257,
    pub debt_delta: i257,
    pub margin_delta: i257,
}

#[starknet::interface]
pub trait IERC20<TContractState> {
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
}

#[starknet::interface]
pub trait IVesuPool<TContractState> {
    fn position(
        self: @TContractState,
        collateral_asset: ContractAddress,
        debt_asset: ContractAddress,
        user: ContractAddress,
    ) -> (Position, u256, u256);
    fn modify_position(
        ref self: TContractState, params: ModifyPositionParams,
    ) -> UpdatePositionResponse;
    fn modify_delegation(ref self: TContractState, delegatee: ContractAddress, delegation: bool);
}

#[starknet::interface]
pub trait IVesuMultiply<TContractState> {
    fn modify_lever(
        ref self: TContractState, modify_lever_params: ModifyLeverParams,
    ) -> ModifyLeverResponse;
}
