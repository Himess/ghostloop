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
        ACTION_BORROW, ACTION_CLOSE_BORROW, ACTION_REPAY, Authorization, hash_authorization,
        hash_borrow_parameters, hash_close_borrow_parameters, hash_repay_parameters,
    };
    use crate::ghost_position::{IGhostPosition, errors};
    use crate::interfaces::{
        Amount, AmountDenomination, IERC20Dispatcher, IERC20DispatcherTrait, IVesuPoolDispatcher,
        IVesuPoolDispatcherTrait, ModifyPositionParams, Position,
    };

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
