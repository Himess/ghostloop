use starknet::{ClassHash, ContractAddress};
use crate::authorization::Authorization;
use crate::interfaces::OpenNoteDeposit;

#[derive(Serde, Copy, Drop, PartialEq, Debug)]
pub struct CreateAndFundInput {
    pub capability_public_key: felt252,
    pub position_salt: felt252,
    pub authorization: Authorization,
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
        input: CreateAndFundInput,
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
    pub const UNAUTHORIZED_CALLER: felt252 = 'UNAUTHORIZED_CALLER';
    pub const INVALID_NONCE: felt252 = 'INVALID_NONCE';
    pub const AUTHORIZATION_EXPIRED: felt252 = 'AUTH_EXPIRED';
    pub const INVALID_SIGNATURE: felt252 = 'INVALID_SIGNATURE';
    pub const POSITION_EXISTS: felt252 = 'POSITION_EXISTS';
    pub const ADDRESS_MISMATCH: felt252 = 'ADDRESS_MISMATCH';
    pub const INSUFFICIENT_FUNDS: felt252 = 'INSUFFICIENT_FUNDS';
    pub const TOKEN_TRANSFER_FAILED: felt252 = 'TOKEN_TRANSFER_FAILED';
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
    use crate::ghostloop_anonymizer::{CreateAndFundInput, IGhostLoopAnonymizer, errors};
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
    }

    #[abi(embed_v0)]
    impl GhostLoopAnonymizerImpl of IGhostLoopAnonymizer<ContractState> {
        fn privacy_invoke(
            ref self: ContractState,
            in_token: ContractAddress,
            out_token: ContractAddress,
            amount: u256,
            input: CreateAndFundInput,
        ) -> Span<OpenNoteDeposit> {
            assert(get_caller_address() == self.privacy_pool.read(), errors::UNAUTHORIZED_CALLER);
            assert(amount.is_non_zero(), errors::ZERO_AMOUNT);
            assert(input.capability_public_key.is_non_zero(), errors::ZERO_PUBLIC_KEY);
            let eth = self.eth.read();
            assert(in_token == eth && out_token == eth, errors::INVALID_TOKEN);

            let key = self.position_key(input.capability_public_key, input.position_salt);
            assert(self.positions.read(key).is_zero(), errors::POSITION_EXISTS);
            let predicted = self.predict_position(input.capability_public_key, input.position_salt);
            self.assert_creation_authorization(predicted, amount, input);

            let self_address = get_contract_address();
            let eth_token = IERC20Dispatcher { contract_address: eth };
            assert(eth_token.balance_of(self_address) >= amount, errors::INSUFFICIENT_FUNDS);
            let constructor_calldata = self.constructor_calldata(input.capability_public_key);
            let (position, _) = deploy_syscall(
                class_hash: self.position_class_hash.read(),
                contract_address_salt: input.position_salt,
                calldata: constructor_calldata.span(),
                deploy_from_zero: false,
            )
                .unwrap_syscall();
            assert(position == predicted, errors::ADDRESS_MISMATCH);
            assert(eth_token.transfer(position, amount), errors::TOKEN_TRANSFER_FAILED);

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
