use starknet::ContractAddress;
use crate::authorization::Authorization;
use crate::interfaces::Position;

#[starknet::interface]
pub trait IGhostPosition<TContractState> {
    fn borrow(
        ref self: TContractState,
        collateral_amount: u256,
        debt_amount: u256,
        minimum_borrowed: u256,
        authorization: Authorization,
    ) -> u256;
    fn repay(ref self: TContractState, repay_amount: u256, authorization: Authorization);
    fn close_borrow(
        ref self: TContractState, maximum_debt_input: u256, authorization: Authorization,
    ) -> (u256, u256);
    fn increase_leverage(
        ref self: TContractState,
        add_margin: u256,
        debt_amount: u128,
        minimum_lever_collateral: u128,
        authorization: Authorization,
    ) -> (u256, u256);
    fn unwind(
        ref self: TContractState,
        maximum_collateral_swap: u128,
        minimum_collateral_returned: u256,
        authorization: Authorization,
    ) -> u256;
    fn read_position(self: @TContractState) -> (Position, u256, u256);
    fn capability_public_key(self: @TContractState) -> felt252;
    fn next_nonce(self: @TContractState) -> u64;
    fn anonymizer(self: @TContractState) -> ContractAddress;
}

pub mod errors {
    pub const ZERO_ADDRESS: felt252 = 'ZERO_ADDRESS';
    pub const ZERO_PUBLIC_KEY: felt252 = 'ZERO_PUBLIC_KEY';
    pub const TOKENS_EQUAL: felt252 = 'TOKENS_EQUAL';
    pub const UNAUTHORIZED_CALLER: felt252 = 'UNAUTHORIZED_CALLER';
    pub const INVALID_NONCE: felt252 = 'INVALID_NONCE';
    pub const AUTHORIZATION_EXPIRED: felt252 = 'AUTH_EXPIRED';
    pub const INVALID_SIGNATURE: felt252 = 'INVALID_SIGNATURE';
    pub const ZERO_AMOUNT: felt252 = 'ZERO_AMOUNT';
    pub const BORROW_SLIPPAGE: felt252 = 'BORROW_SLIPPAGE';
    pub const MAX_DEBT_EXCEEDED: felt252 = 'MAX_DEBT_EXCEEDED';
    pub const TOKEN_APPROVE_FAILED: felt252 = 'TOKEN_APPROVE_FAILED';
    pub const TOKEN_TRANSFER_FAILED: felt252 = 'TOKEN_TRANSFER_FAILED';
    pub const AMOUNT_OVERFLOW: felt252 = 'AMOUNT_OVERFLOW';
    pub const MULTIPLY_MISMATCH: felt252 = 'MULTIPLY_MISMATCH';
    pub const POSITION_NOT_CLOSED: felt252 = 'POSITION_NOT_CLOSED';
    pub const UNWIND_SLIPPAGE: felt252 = 'UNWIND_SLIPPAGE';
}

#[starknet::contract]
pub mod GhostPosition {
    use alexandria_math::i257::I257Trait;
    use core::ecdsa::check_ecdsa_signature;
    use core::num::traits::Zero;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{
        ContractAddress, get_block_timestamp, get_caller_address, get_contract_address, get_tx_info,
    };
    use crate::authorization::{
        ACTION_BORROW, ACTION_CLOSE_BORROW, ACTION_INCREASE_LEVERAGE, ACTION_REPAY, ACTION_UNWIND,
        Authorization, hash_authorization, hash_borrow_parameters, hash_close_borrow_parameters,
        hash_increase_leverage_parameters, hash_repay_parameters, hash_unwind_parameters,
    };
    use crate::ghost_position::{IGhostPosition, errors};
    use crate::interfaces::{
        Amount, AmountDenomination, DecreaseLeverParams, EkuboPoolKey, IERC20Dispatcher,
        IERC20DispatcherTrait, IVesuMultiplyDispatcher, IVesuMultiplyDispatcherTrait,
        IVesuPoolDispatcher, IVesuPoolDispatcherTrait, IncreaseLeverParams, ModifyLeverAction,
        ModifyLeverParams, ModifyPositionParams, Position, RouteNode, SignedI129, Swap, TokenAmount,
    };

    const EKUBO_ETH_USDC_FEE: u128 = 170141183460469235273462165868118016;
    const EKUBO_ETH_USDC_TICK_SPACING: u128 = 1000;
    const MIN_SQRT_RATIO_LIMIT: u256 = 18446748437148339061;
    const MAX_SQRT_RATIO_LIMIT: u256 = 6277100250585753475930931601400621808602321654880405518632;
    const SCALE_128: u128 = 1_000_000_000_000_000_000;

    #[storage]
    struct Storage {
        anonymizer: ContractAddress,
        capability_public_key: felt252,
        next_nonce: u64,
        eth: ContractAddress,
        usdc: ContractAddress,
        vesu_pool: ContractAddress,
        vesu_multiply: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Borrowed: Borrowed,
        Repaid: Repaid,
        BorrowClosed: BorrowClosed,
        LeverageIncreased: LeverageIncreased,
        Unwound: Unwound,
    }

    #[derive(Drop, starknet::Event)]
    struct Borrowed {
        collateral_amount: u256,
        debt_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Repaid {
        repay_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct BorrowClosed {
        collateral_returned: u256,
        debt_refund: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct LeverageIncreased {
        margin_added: u256,
        collateral_added: u256,
        debt_added: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Unwound {
        collateral_returned: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        anonymizer: ContractAddress,
        capability_public_key: felt252,
        eth: ContractAddress,
        usdc: ContractAddress,
        vesu_pool: ContractAddress,
        vesu_multiply: ContractAddress,
    ) {
        assert(anonymizer.is_non_zero(), errors::ZERO_ADDRESS);
        assert(eth.is_non_zero(), errors::ZERO_ADDRESS);
        assert(usdc.is_non_zero(), errors::ZERO_ADDRESS);
        assert(vesu_pool.is_non_zero(), errors::ZERO_ADDRESS);
        assert(vesu_multiply.is_non_zero(), errors::ZERO_ADDRESS);
        assert(capability_public_key.is_non_zero(), errors::ZERO_PUBLIC_KEY);
        assert(eth != usdc, errors::TOKENS_EQUAL);

        self.anonymizer.write(anonymizer);
        self.capability_public_key.write(capability_public_key);
        self.next_nonce.write(0);
        self.eth.write(eth);
        self.usdc.write(usdc);
        self.vesu_pool.write(vesu_pool);
        self.vesu_multiply.write(vesu_multiply);
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn assert_and_consume_authorization(
            ref self: ContractState,
            action: felt252,
            parameters_hash: felt252,
            authorization: Authorization,
        ) {
            assert(get_caller_address() == self.anonymizer.read(), errors::UNAUTHORIZED_CALLER);
            let expected_nonce = self.next_nonce.read();
            assert(authorization.nonce == expected_nonce, errors::INVALID_NONCE);
            assert(get_block_timestamp() <= authorization.deadline, errors::AUTHORIZATION_EXPIRED);

            let message_hash = hash_authorization(
                chain_id: get_tx_info().unbox().chain_id,
                position: get_contract_address(),
                :action,
                :parameters_hash,
                nonce: authorization.nonce,
                deadline: authorization.deadline,
            );
            assert(
                check_ecdsa_signature(
                    message_hash,
                    self.capability_public_key.read(),
                    authorization.signature_r,
                    authorization.signature_s,
                ),
                errors::INVALID_SIGNATURE,
            );
            self.next_nonce.write(expected_nonce + 1);
        }

        fn approve_or_revert(
            self: @ContractState, token: ContractAddress, spender: ContractAddress, amount: u256,
        ) {
            assert(
                IERC20Dispatcher { contract_address: token }.approve(:spender, :amount),
                errors::TOKEN_APPROVE_FAILED,
            );
        }

        fn transfer_or_revert(
            self: @ContractState, token: ContractAddress, recipient: ContractAddress, amount: u256,
        ) {
            if amount.is_non_zero() {
                assert(
                    IERC20Dispatcher { contract_address: token }.transfer(:recipient, :amount),
                    errors::TOKEN_TRANSFER_FAILED,
                );
            }
        }

        fn eth_usdc_pool_key(self: @ContractState) -> EkuboPoolKey {
            EkuboPoolKey {
                token0: self.eth.read(),
                token1: self.usdc.read(),
                fee: EKUBO_ETH_USDC_FEE,
                tick_spacing: EKUBO_ETH_USDC_TICK_SPACING,
                extension: 0.try_into().unwrap(),
            }
        }
    }

    #[abi(embed_v0)]
    impl GhostPositionImpl of IGhostPosition<ContractState> {
        fn borrow(
            ref self: ContractState,
            collateral_amount: u256,
            debt_amount: u256,
            minimum_borrowed: u256,
            authorization: Authorization,
        ) -> u256 {
            assert(collateral_amount.is_non_zero(), errors::ZERO_AMOUNT);
            assert(debt_amount.is_non_zero(), errors::ZERO_AMOUNT);
            self
                .assert_and_consume_authorization(
                    action: ACTION_BORROW,
                    parameters_hash: hash_borrow_parameters(
                        collateral_amount, debt_amount, minimum_borrowed,
                    ),
                    :authorization,
                );

            let eth = self.eth.read();
            let usdc = self.usdc.read();
            let vesu_pool = self.vesu_pool.read();
            let position_address = get_contract_address();
            let usdc_token = IERC20Dispatcher { contract_address: usdc };
            let usdc_before = usdc_token.balance_of(position_address);

            self.approve_or_revert(eth, vesu_pool, collateral_amount);
            IVesuPoolDispatcher { contract_address: vesu_pool }
                .modify_position(
                    ModifyPositionParams {
                        collateral_asset: eth,
                        debt_asset: usdc,
                        user: position_address,
                        collateral: Amount {
                            denomination: AmountDenomination::Assets,
                            value: I257Trait::new(collateral_amount, false),
                        },
                        debt: Amount {
                            denomination: AmountDenomination::Assets,
                            value: I257Trait::new(debt_amount, false),
                        },
                    },
                );

            let borrowed = usdc_token.balance_of(position_address) - usdc_before;
            assert(borrowed >= minimum_borrowed, errors::BORROW_SLIPPAGE);
            self.transfer_or_revert(usdc, self.anonymizer.read(), borrowed);
            self.emit(Borrowed { collateral_amount, debt_amount: borrowed });
            borrowed
        }

        fn repay(ref self: ContractState, repay_amount: u256, authorization: Authorization) {
            assert(repay_amount.is_non_zero(), errors::ZERO_AMOUNT);
            self
                .assert_and_consume_authorization(
                    action: ACTION_REPAY,
                    parameters_hash: hash_repay_parameters(repay_amount),
                    :authorization,
                );

            let usdc = self.usdc.read();
            let vesu_pool = self.vesu_pool.read();
            self.approve_or_revert(usdc, vesu_pool, repay_amount);
            IVesuPoolDispatcher { contract_address: vesu_pool }
                .modify_position(
                    ModifyPositionParams {
                        collateral_asset: self.eth.read(),
                        debt_asset: usdc,
                        user: get_contract_address(),
                        collateral: Amount {
                            denomination: AmountDenomination::Native,
                            value: I257Trait::new(0, false),
                        },
                        debt: Amount {
                            denomination: AmountDenomination::Assets,
                            value: I257Trait::new(repay_amount, true),
                        },
                    },
                );
            self.emit(Repaid { repay_amount });
        }

        fn close_borrow(
            ref self: ContractState, maximum_debt_input: u256, authorization: Authorization,
        ) -> (u256, u256) {
            self
                .assert_and_consume_authorization(
                    action: ACTION_CLOSE_BORROW,
                    parameters_hash: hash_close_borrow_parameters(maximum_debt_input),
                    :authorization,
                );

            let eth = self.eth.read();
            let usdc = self.usdc.read();
            let vesu_pool = self.vesu_pool.read();
            let position_address = get_contract_address();
            let pool = IVesuPoolDispatcher { contract_address: vesu_pool };
            let (position, _, current_debt) = pool.position(eth, usdc, position_address);
            assert(current_debt <= maximum_debt_input, errors::MAX_DEBT_EXCEEDED);
            self.approve_or_revert(usdc, vesu_pool, maximum_debt_input);

            pool
                .modify_position(
                    ModifyPositionParams {
                        collateral_asset: eth,
                        debt_asset: usdc,
                        user: position_address,
                        collateral: Amount {
                            denomination: AmountDenomination::Native,
                            value: I257Trait::new(position.collateral_shares, true),
                        },
                        debt: Amount {
                            denomination: AmountDenomination::Native,
                            value: I257Trait::new(position.nominal_debt, true),
                        },
                    },
                );

            let collateral_returned = IERC20Dispatcher { contract_address: eth }
                .balance_of(position_address);
            let debt_refund = IERC20Dispatcher { contract_address: usdc }
                .balance_of(position_address);
            let recipient = self.anonymizer.read();
            self.transfer_or_revert(eth, recipient, collateral_returned);
            self.transfer_or_revert(usdc, recipient, debt_refund);
            self.emit(BorrowClosed { collateral_returned, debt_refund });
            (collateral_returned, debt_refund)
        }

        fn increase_leverage(
            ref self: ContractState,
            add_margin: u256,
            debt_amount: u128,
            minimum_lever_collateral: u128,
            authorization: Authorization,
        ) -> (u256, u256) {
            assert(add_margin.is_non_zero(), errors::ZERO_AMOUNT);
            assert(debt_amount != 0, errors::ZERO_AMOUNT);
            let margin_u128: u128 = add_margin.try_into().expect(errors::AMOUNT_OVERFLOW);
            self
                .assert_and_consume_authorization(
                    action: ACTION_INCREASE_LEVERAGE,
                    parameters_hash: hash_increase_leverage_parameters(
                        add_margin, debt_amount, minimum_lever_collateral,
                    ),
                    :authorization,
                );

            let eth = self.eth.read();
            let usdc = self.usdc.read();
            let vesu_pool = self.vesu_pool.read();
            let vesu_multiply = self.vesu_multiply.read();
            let position_address = get_contract_address();
            let pool = IVesuPoolDispatcher { contract_address: vesu_pool };
            let (_, collateral_before, debt_before) = pool.position(eth, usdc, position_address);

            pool.modify_delegation(vesu_multiply, true);
            self.approve_or_revert(eth, vesu_multiply, add_margin);
            let response = IVesuMultiplyDispatcher { contract_address: vesu_multiply }
                .modify_lever(
                    ModifyLeverParams {
                        action: ModifyLeverAction::IncreaseLever(
                            IncreaseLeverParams {
                                pool: vesu_pool,
                                collateral_asset: eth,
                                debt_asset: usdc,
                                user: position_address,
                                add_margin: margin_u128,
                                margin_swap: array![],
                                margin_swap_limit_amount: 0,
                                lever_swap: array![
                                    Swap {
                                        route: array![
                                            RouteNode {
                                                pool_key: self.eth_usdc_pool_key(),
                                                sqrt_ratio_limit: MAX_SQRT_RATIO_LIMIT,
                                                skip_ahead: 0,
                                            },
                                        ],
                                        token_amount: TokenAmount {
                                            token: usdc,
                                            amount: SignedI129 { mag: debt_amount, sign: false },
                                        },
                                    },
                                ],
                                lever_swap_limit_amount: minimum_lever_collateral,
                            },
                        ),
                    },
                );
            assert(
                !response.debt_delta.is_negative()
                    && response.debt_delta.abs() == debt_amount.into(),
                errors::MULTIPLY_MISMATCH,
            );

            let (_, collateral_after, debt_after) = pool.position(eth, usdc, position_address);
            assert(
                collateral_after > collateral_before && debt_after > debt_before,
                errors::MULTIPLY_MISMATCH,
            );
            let collateral_added = collateral_after - collateral_before;
            let debt_added = debt_after - debt_before;
            self.emit(LeverageIncreased { margin_added: add_margin, collateral_added, debt_added });
            (collateral_added, debt_added)
        }

        fn unwind(
            ref self: ContractState,
            maximum_collateral_swap: u128,
            minimum_collateral_returned: u256,
            authorization: Authorization,
        ) -> u256 {
            assert(maximum_collateral_swap != 0, errors::ZERO_AMOUNT);
            self
                .assert_and_consume_authorization(
                    action: ACTION_UNWIND,
                    parameters_hash: hash_unwind_parameters(
                        maximum_collateral_swap, minimum_collateral_returned,
                    ),
                    :authorization,
                );

            let eth = self.eth.read();
            let usdc = self.usdc.read();
            let vesu_pool = self.vesu_pool.read();
            let position_address = get_contract_address();
            let pool = IVesuPoolDispatcher { contract_address: vesu_pool };
            let (before, _, debt_before) = pool.position(eth, usdc, position_address);
            assert(
                before.collateral_shares.is_non_zero() && before.nominal_debt.is_non_zero(),
                errors::ZERO_AMOUNT,
            );

            let response = IVesuMultiplyDispatcher { contract_address: self.vesu_multiply.read() }
                .modify_lever(
                    ModifyLeverParams {
                        action: ModifyLeverAction::DecreaseLever(
                            DecreaseLeverParams {
                                pool: vesu_pool,
                                collateral_asset: eth,
                                debt_asset: usdc,
                                user: position_address,
                                sub_margin: 0,
                                recipient: position_address,
                                lever_swap: array![
                                    Swap {
                                        route: array![
                                            RouteNode {
                                                pool_key: self.eth_usdc_pool_key(),
                                                sqrt_ratio_limit: MIN_SQRT_RATIO_LIMIT,
                                                skip_ahead: 0,
                                            },
                                        ],
                                        token_amount: TokenAmount {
                                            token: usdc, amount: SignedI129 { mag: 0, sign: false },
                                        },
                                    },
                                ],
                                lever_swap_limit_amount: maximum_collateral_swap,
                                lever_swap_weights: array![SCALE_128],
                                withdraw_swap: array![],
                                withdraw_swap_limit_amount: 0,
                                withdraw_swap_weights: array![],
                                close_position: true,
                            },
                        ),
                    },
                );
            assert(
                response.debt_delta.is_negative() && response.debt_delta.abs() == debt_before,
                errors::MULTIPLY_MISMATCH,
            );

            let (after, collateral_after, debt_after) = pool.position(eth, usdc, position_address);
            assert(
                after.collateral_shares.is_zero()
                    && after.nominal_debt.is_zero()
                    && collateral_after.is_zero()
                    && debt_after.is_zero(),
                errors::POSITION_NOT_CLOSED,
            );
            let collateral_returned = IERC20Dispatcher { contract_address: eth }
                .balance_of(position_address);
            assert(collateral_returned >= minimum_collateral_returned, errors::UNWIND_SLIPPAGE);
            self.transfer_or_revert(eth, self.anonymizer.read(), collateral_returned);
            self.emit(Unwound { collateral_returned });
            collateral_returned
        }

        fn read_position(self: @ContractState) -> (Position, u256, u256) {
            IVesuPoolDispatcher { contract_address: self.vesu_pool.read() }
                .position(self.eth.read(), self.usdc.read(), get_contract_address())
        }

        fn capability_public_key(self: @ContractState) -> felt252 {
            self.capability_public_key.read()
        }

        fn next_nonce(self: @ContractState) -> u64 {
            self.next_nonce.read()
        }

        fn anonymizer(self: @ContractState) -> ContractAddress {
            self.anonymizer.read()
        }
    }
}
