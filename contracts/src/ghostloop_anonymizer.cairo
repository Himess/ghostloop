use starknet::{ClassHash, ContractAddress};
use crate::authorization::Authorization;
use crate::interfaces::OpenNoteDeposit;

#[derive(Serde, Copy, Drop, PartialEq, Debug)]
pub struct CreateAndFundInput {
    pub capability_public_key: felt252,
    pub position_salt: felt252,
    pub authorization: Authorization,
}

#[derive(Serde, Copy, Drop, PartialEq, Debug)]
pub struct BorrowInput {
    pub capability_public_key: felt252,
    pub position_salt: felt252,
    pub debt_amount: u256,
    pub minimum_borrowed: u256,
    pub note_id: felt252,
    pub authorization: Authorization,
}

#[derive(Serde, Copy, Drop, PartialEq, Debug)]
pub struct RepayInput {
    pub capability_public_key: felt252,
    pub position_salt: felt252,
    pub authorization: Authorization,
}

#[derive(Serde, Copy, Drop, PartialEq, Debug)]
pub struct CloseBorrowInput {
    pub capability_public_key: felt252,
    pub position_salt: felt252,
    pub collateral_note_id: felt252,
    /// Must be zero when no USDC refund is expected. A non-zero refund requires
    /// a second open note id so no pool-created note is left unused.
    pub debt_refund_note_id: felt252,
    pub authorization: Authorization,
}

#[derive(Serde, Copy, Drop, PartialEq, Debug)]
pub struct IncreaseLeverageInput {
    pub capability_public_key: felt252,
    pub position_salt: felt252,
    pub debt_amount: u128,
    pub minimum_lever_collateral: u128,
    pub authorization: Authorization,
}

#[derive(Serde, Copy, Drop, PartialEq, Debug)]
pub struct UnwindInput {
    pub capability_public_key: felt252,
    pub position_salt: felt252,
    pub maximum_collateral_swap: u128,
    pub minimum_collateral_returned: u256,
    pub collateral_note_id: felt252,
    pub authorization: Authorization,
}

#[derive(Serde, Copy, Drop, PartialEq, Debug)]
pub enum GhostLoopOperation {
    CreateAndFund: CreateAndFundInput,
    Borrow: BorrowInput,
    Repay: RepayInput,
    CloseBorrow: CloseBorrowInput,
    IncreaseLeverage: IncreaseLeverageInput,
    Unwind: UnwindInput,
}

#[starknet::interface]
pub trait IGhostLoopAnonymizer<TContractState> {
    /// STRK20 invokes this selector. The first three fields retain the documented
    /// private-DeFi token/token/amount convention used by Wallet API actions.
    fn privacy_invoke(
        ref self: TContractState,
        in_token: ContractAddress,
        out_token: ContractAddress,
        amount: u256,
        operation: GhostLoopOperation,
    ) -> Span<OpenNoteDeposit>;
    fn predict_position(
        self: @TContractState, capability_public_key: felt252, position_salt: felt252,
    ) -> ContractAddress;
    fn get_position(
        self: @TContractState, capability_public_key: felt252, position_salt: felt252,
    ) -> ContractAddress;
    fn privacy_pool(self: @TContractState) -> ContractAddress;
    fn position_class_hash(self: @TContractState) -> ClassHash;
}

pub mod errors {
    pub const ZERO_ADDRESS: felt252 = 'ZERO_ADDRESS';
    pub const ZERO_CLASS_HASH: felt252 = 'ZERO_CLASS_HASH';
    pub const ZERO_PUBLIC_KEY: felt252 = 'ZERO_PUBLIC_KEY';
    pub const ZERO_AMOUNT: felt252 = 'ZERO_AMOUNT';
    pub const INVALID_TOKEN: felt252 = 'INVALID_TOKEN';
    pub const TOKENS_EQUAL: felt252 = 'TOKENS_EQUAL';
    pub const UNAUTHORIZED_CALLER: felt252 = 'UNAUTHORIZED_CALLER';
    pub const INVALID_NONCE: felt252 = 'INVALID_NONCE';
    pub const AUTHORIZATION_EXPIRED: felt252 = 'AUTH_EXPIRED';
    pub const INVALID_SIGNATURE: felt252 = 'INVALID_SIGNATURE';
    pub const POSITION_EXISTS: felt252 = 'POSITION_EXISTS';
    pub const ADDRESS_MISMATCH: felt252 = 'ADDRESS_MISMATCH';
    pub const INSUFFICIENT_FUNDS: felt252 = 'INSUFFICIENT_FUNDS';
    pub const TOKEN_TRANSFER_FAILED: felt252 = 'TOKEN_TRANSFER_FAILED';
    pub const TOKEN_APPROVE_FAILED: felt252 = 'TOKEN_APPROVE_FAILED';
    pub const POSITION_NOT_FOUND: felt252 = 'POSITION_NOT_FOUND';
    pub const INPUT_TRANSFER_MISMATCH: felt252 = 'INPUT_XFER_MISMATCH';
    pub const NEGATIVE_OUTPUT: felt252 = 'NEGATIVE_OUTPUT';
    pub const OUTPUT_MISMATCH: felt252 = 'OUTPUT_MISMATCH';
    pub const OUTPUT_OVERFLOW: felt252 = 'OUTPUT_OVERFLOW';
    pub const ZERO_OUT_AMOUNT: felt252 = 'ZERO_OUT_AMOUNT';
    pub const NOTE_ID_REQUIRED: felt252 = 'NOTE_ID_REQUIRED';
    pub const UNEXPECTED_NOTE_ID: felt252 = 'UNEXPECTED_NOTE_ID';
}

#[starknet::contract]
pub mod GhostLoopAnonymizer {
    use core::ecdsa::check_ecdsa_signature;
    use core::hash::HashStateTrait;
    use core::num::traits::Zero;
    use core::poseidon::PoseidonTrait;
    use openzeppelin::utils::deployments::calculate_contract_address_from_deploy_syscall;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::syscalls::deploy_syscall;
    use starknet::{
        ClassHash, ContractAddress, SyscallResultTrait, get_block_timestamp, get_caller_address,
        get_contract_address, get_tx_info,
    };
    use crate::authorization::{
        ACTION_CREATE_AND_FUND, hash_authorization, hash_create_and_fund_parameters,
    };
    use crate::ghost_position::{IGhostPositionDispatcher, IGhostPositionDispatcherTrait};
    use crate::ghostloop_anonymizer::{
        BorrowInput, CloseBorrowInput, CreateAndFundInput, GhostLoopOperation, IGhostLoopAnonymizer,
        IncreaseLeverageInput, RepayInput, UnwindInput, errors,
    };
    use crate::interfaces::{IERC20Dispatcher, IERC20DispatcherTrait, OpenNoteDeposit};

    #[storage]
    struct Storage {
        privacy_pool: ContractAddress,
        position_class_hash: ClassHash,
        eth: ContractAddress,
        usdc: ContractAddress,
        vesu_pool: ContractAddress,
        vesu_multiply: ContractAddress,
        positions: Map<felt252, ContractAddress>,
    }

    #[derive(Drop, starknet::Event)]
    struct PositionCreated {
        #[key]
        position: ContractAddress,
        capability_public_key: felt252,
        position_salt: felt252,
        funded_amount: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        PositionCreated: PositionCreated,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        privacy_pool: ContractAddress,
        position_class_hash: ClassHash,
        eth: ContractAddress,
        usdc: ContractAddress,
        vesu_pool: ContractAddress,
        vesu_multiply: ContractAddress,
    ) {
        assert(privacy_pool.is_non_zero(), errors::ZERO_ADDRESS);
        assert(eth.is_non_zero(), errors::ZERO_ADDRESS);
        assert(usdc.is_non_zero(), errors::ZERO_ADDRESS);
        assert(vesu_pool.is_non_zero(), errors::ZERO_ADDRESS);
        assert(vesu_multiply.is_non_zero(), errors::ZERO_ADDRESS);
        assert(eth != usdc, errors::TOKENS_EQUAL);
        let class_hash_felt: felt252 = position_class_hash.into();
        assert(class_hash_felt.is_non_zero(), errors::ZERO_CLASS_HASH);

        self.privacy_pool.write(privacy_pool);
        self.position_class_hash.write(position_class_hash);
        self.eth.write(eth);
        self.usdc.write(usdc);
        self.vesu_pool.write(vesu_pool);
        self.vesu_multiply.write(vesu_multiply);
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn position_key(
            self: @ContractState, capability_public_key: felt252, position_salt: felt252,
        ) -> felt252 {
            PoseidonTrait::new().update(capability_public_key).update(position_salt).finalize()
        }

        fn constructor_calldata(
            self: @ContractState, capability_public_key: felt252,
        ) -> Array<felt252> {
            array![
                get_contract_address().into(), capability_public_key, self.eth.read().into(),
                self.usdc.read().into(), self.vesu_pool.read().into(),
                self.vesu_multiply.read().into(),
            ]
        }

        fn assert_creation_authorization(
            self: @ContractState,
            position: ContractAddress,
            amount: u256,
            input: CreateAndFundInput,
        ) {
            assert(input.authorization.nonce == 0, errors::INVALID_NONCE);
            assert(
                get_block_timestamp() <= input.authorization.deadline,
                errors::AUTHORIZATION_EXPIRED,
            );
            let message_hash = hash_authorization(
                chain_id: get_tx_info().unbox().chain_id,
                :position,
                action: ACTION_CREATE_AND_FUND,
                parameters_hash: hash_create_and_fund_parameters(
                    amount, input.capability_public_key, input.position_salt,
                ),
                nonce: input.authorization.nonce,
                deadline: input.authorization.deadline,
            );
            assert(
                check_ecdsa_signature(
                    message_hash,
                    input.capability_public_key,
                    input.authorization.signature_r,
                    input.authorization.signature_s,
                ),
                errors::INVALID_SIGNATURE,
            );
        }

        fn position_or_revert(
            self: @ContractState, capability_public_key: felt252, position_salt: felt252,
        ) -> ContractAddress {
            assert(capability_public_key.is_non_zero(), errors::ZERO_PUBLIC_KEY);
            let position = self
                .positions
                .read(self.position_key(capability_public_key, position_salt));
            assert(position.is_non_zero(), errors::POSITION_NOT_FOUND);
            position
        }

        fn transfer_exact(
            self: @ContractState, token: ContractAddress, recipient: ContractAddress, amount: u256,
        ) {
            let self_address = get_contract_address();
            let erc20 = IERC20Dispatcher { contract_address: token };
            let balance_before = erc20.balance_of(self_address);
            assert(balance_before >= amount, errors::INSUFFICIENT_FUNDS);
            assert(erc20.transfer(recipient, amount), errors::TOKEN_TRANSFER_FAILED);
            let balance_after = erc20.balance_of(self_address);
            assert(
                balance_before >= balance_after && balance_before - balance_after == amount,
                errors::INPUT_TRANSFER_MISMATCH,
            );
        }

        fn measured_delta(
            self: @ContractState, token: ContractAddress, balance_before: u256,
        ) -> u256 {
            let balance_after = IERC20Dispatcher { contract_address: token }
                .balance_of(get_contract_address());
            assert(balance_after >= balance_before, errors::NEGATIVE_OUTPUT);
            balance_after - balance_before
        }

        fn checked_note_amount(self: @ContractState, amount: u256) -> u128 {
            let note_amount: u128 = amount.try_into().expect(errors::OUTPUT_OVERFLOW);
            assert(note_amount.is_non_zero(), errors::ZERO_OUT_AMOUNT);
            note_amount
        }

        fn approve_pool(self: @ContractState, token: ContractAddress, amount: u256) {
            assert(
                IERC20Dispatcher { contract_address: token }
                    .approve(self.privacy_pool.read(), amount),
                errors::TOKEN_APPROVE_FAILED,
            );
        }

        fn create_and_fund(
            ref self: ContractState,
            in_token: ContractAddress,
            out_token: ContractAddress,
            amount: u256,
            input: CreateAndFundInput,
        ) -> Span<OpenNoteDeposit> {
            assert(input.capability_public_key.is_non_zero(), errors::ZERO_PUBLIC_KEY);
            let eth = self.eth.read();
            assert(in_token == eth && out_token == eth, errors::INVALID_TOKEN);

            let key = self.position_key(input.capability_public_key, input.position_salt);
            assert(self.positions.read(key).is_zero(), errors::POSITION_EXISTS);
            let predicted = self.predict_position(input.capability_public_key, input.position_salt);
            self.assert_creation_authorization(predicted, amount, input);

            let constructor_calldata = self.constructor_calldata(input.capability_public_key);
            let (position, _) = deploy_syscall(
                class_hash: self.position_class_hash.read(),
                contract_address_salt: input.position_salt,
                calldata: constructor_calldata.span(),
                deploy_from_zero: false,
            )
                .unwrap_syscall();
            assert(position == predicted, errors::ADDRESS_MISMATCH);
            self.transfer_exact(eth, position, amount);

            self.positions.write(key, position);
            self
                .emit(
                    PositionCreated {
                        position,
                        capability_public_key: input.capability_public_key,
                        position_salt: input.position_salt,
                        funded_amount: amount,
                    },
                );
            array![].span()
        }

        fn borrow(
            ref self: ContractState,
            in_token: ContractAddress,
            out_token: ContractAddress,
            collateral_amount: u256,
            input: BorrowInput,
        ) -> Span<OpenNoteDeposit> {
            let eth = self.eth.read();
            let usdc = self.usdc.read();
            assert(in_token == eth && out_token == usdc, errors::INVALID_TOKEN);
            assert(input.note_id.is_non_zero(), errors::NOTE_ID_REQUIRED);
            let position = self
                .position_or_revert(input.capability_public_key, input.position_salt);

            self.transfer_exact(eth, position, collateral_amount);
            let balance_before = IERC20Dispatcher { contract_address: usdc }
                .balance_of(get_contract_address());
            let reported = IGhostPositionDispatcher { contract_address: position }
                .borrow(
                    collateral_amount,
                    input.debt_amount,
                    input.minimum_borrowed,
                    input.authorization,
                );
            let received = self.measured_delta(usdc, balance_before);
            assert(received == reported, errors::OUTPUT_MISMATCH);
            let note_amount = self.checked_note_amount(received);
            self.approve_pool(usdc, received);

            array![OpenNoteDeposit { note_id: input.note_id, token: usdc, amount: note_amount }]
                .span()
        }

        fn repay(
            ref self: ContractState,
            in_token: ContractAddress,
            out_token: ContractAddress,
            repay_amount: u256,
            input: RepayInput,
        ) -> Span<OpenNoteDeposit> {
            let usdc = self.usdc.read();
            assert(in_token == usdc && out_token == usdc, errors::INVALID_TOKEN);
            let position = self
                .position_or_revert(input.capability_public_key, input.position_salt);
            self.transfer_exact(usdc, position, repay_amount);
            IGhostPositionDispatcher { contract_address: position }
                .repay(repay_amount, input.authorization);
            array![].span()
        }

        fn close_borrow(
            ref self: ContractState,
            in_token: ContractAddress,
            out_token: ContractAddress,
            maximum_debt_input: u256,
            input: CloseBorrowInput,
        ) -> Span<OpenNoteDeposit> {
            let eth = self.eth.read();
            let usdc = self.usdc.read();
            assert(in_token == usdc && out_token == eth, errors::INVALID_TOKEN);
            assert(input.collateral_note_id.is_non_zero(), errors::NOTE_ID_REQUIRED);
            let position = self
                .position_or_revert(input.capability_public_key, input.position_salt);

            self.transfer_exact(usdc, position, maximum_debt_input);
            let self_address = get_contract_address();
            let eth_before = IERC20Dispatcher { contract_address: eth }.balance_of(self_address);
            let usdc_before = IERC20Dispatcher { contract_address: usdc }.balance_of(self_address);
            let (reported_collateral, reported_refund) = IGhostPositionDispatcher {
                contract_address: position,
            }
                .close_borrow(maximum_debt_input, input.authorization);
            let collateral_received = self.measured_delta(eth, eth_before);
            let refund_received = self.measured_delta(usdc, usdc_before);
            assert(
                collateral_received == reported_collateral && refund_received == reported_refund,
                errors::OUTPUT_MISMATCH,
            );

            let collateral_note_amount = self.checked_note_amount(collateral_received);
            self.approve_pool(eth, collateral_received);
            let mut deposits = array![
                OpenNoteDeposit {
                    note_id: input.collateral_note_id, token: eth, amount: collateral_note_amount,
                },
            ];
            if refund_received.is_non_zero() {
                assert(input.debt_refund_note_id.is_non_zero(), errors::NOTE_ID_REQUIRED);
                let refund_note_amount = self.checked_note_amount(refund_received);
                self.approve_pool(usdc, refund_received);
                deposits
                    .append(
                        OpenNoteDeposit {
                            note_id: input.debt_refund_note_id,
                            token: usdc,
                            amount: refund_note_amount,
                        },
                    );
            } else {
                assert(input.debt_refund_note_id == 0, errors::UNEXPECTED_NOTE_ID);
            }
            deposits.span()
        }

        fn increase_leverage(
            ref self: ContractState,
            in_token: ContractAddress,
            out_token: ContractAddress,
            add_margin: u256,
            input: IncreaseLeverageInput,
        ) -> Span<OpenNoteDeposit> {
            let eth = self.eth.read();
            assert(in_token == eth && out_token == eth, errors::INVALID_TOKEN);
            let position = self
                .position_or_revert(input.capability_public_key, input.position_salt);
            self.transfer_exact(eth, position, add_margin);
            IGhostPositionDispatcher { contract_address: position }
                .increase_leverage(
                    add_margin,
                    input.debt_amount,
                    input.minimum_lever_collateral,
                    input.authorization,
                );
            array![].span()
        }

        fn unwind(
            ref self: ContractState,
            in_token: ContractAddress,
            out_token: ContractAddress,
            settlement_anchor: u256,
            input: UnwindInput,
        ) -> Span<OpenNoteDeposit> {
            let eth = self.eth.read();
            assert(in_token == eth && out_token == eth, errors::INVALID_TOKEN);
            assert(input.collateral_note_id.is_non_zero(), errors::NOTE_ID_REQUIRED);
            let position = self
                .position_or_revert(input.capability_public_key, input.position_salt);
            self.transfer_exact(eth, position, settlement_anchor);

            let balance_before = IERC20Dispatcher { contract_address: eth }
                .balance_of(get_contract_address());
            let reported = IGhostPositionDispatcher { contract_address: position }
                .unwind(
                    input.maximum_collateral_swap,
                    input.minimum_collateral_returned,
                    input.authorization,
                );
            let received = self.measured_delta(eth, balance_before);
            assert(received == reported, errors::OUTPUT_MISMATCH);
            let note_amount = self.checked_note_amount(received);
            self.approve_pool(eth, received);
            array![
                OpenNoteDeposit {
                    note_id: input.collateral_note_id, token: eth, amount: note_amount,
                },
            ]
                .span()
        }
    }

    #[abi(embed_v0)]
    impl GhostLoopAnonymizerImpl of IGhostLoopAnonymizer<ContractState> {
        fn privacy_invoke(
            ref self: ContractState,
            in_token: ContractAddress,
            out_token: ContractAddress,
            amount: u256,
            operation: GhostLoopOperation,
        ) -> Span<OpenNoteDeposit> {
            assert(get_caller_address() == self.privacy_pool.read(), errors::UNAUTHORIZED_CALLER);
            assert(amount.is_non_zero(), errors::ZERO_AMOUNT);
            match operation {
                GhostLoopOperation::CreateAndFund(input) => {
                    self.create_and_fund(in_token, out_token, amount, input)
                },
                GhostLoopOperation::Borrow(input) => {
                    self.borrow(in_token, out_token, amount, input)
                },
                GhostLoopOperation::Repay(input) => {
                    self.repay(in_token, out_token, amount, input)
                },
                GhostLoopOperation::CloseBorrow(input) => {
                    self.close_borrow(in_token, out_token, amount, input)
                },
                GhostLoopOperation::IncreaseLeverage(input) => {
                    self.increase_leverage(in_token, out_token, amount, input)
                },
                GhostLoopOperation::Unwind(input) => {
                    self.unwind(in_token, out_token, amount, input)
                },
            }
        }

        fn predict_position(
            self: @ContractState, capability_public_key: felt252, position_salt: felt252,
        ) -> ContractAddress {
            let constructor_calldata = self.constructor_calldata(capability_public_key);
            calculate_contract_address_from_deploy_syscall(
                salt: position_salt,
                class_hash: self.position_class_hash.read(),
                constructor_calldata: constructor_calldata.span(),
                deployer_address: get_contract_address(),
            )
        }

        fn get_position(
            self: @ContractState, capability_public_key: felt252, position_salt: felt252,
        ) -> ContractAddress {
            self.positions.read(self.position_key(capability_public_key, position_salt))
        }

        fn privacy_pool(self: @ContractState) -> ContractAddress {
            self.privacy_pool.read()
        }

        fn position_class_hash(self: @ContractState) -> ClassHash {
            self.position_class_hash.read()
        }
    }
}
