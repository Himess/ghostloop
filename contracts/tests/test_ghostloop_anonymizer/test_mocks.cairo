use starknet::ContractAddress;

#[starknet::interface]
pub trait IMockERC20<TContractState> {
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn mint(ref self: TContractState, recipient: ContractAddress, amount: u256);
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
}

#[starknet::contract]
pub mod MockERC20 {
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use starknet::{ContractAddress, get_caller_address};
    use super::IMockERC20;

    #[storage]
    struct Storage {
        balances: Map<ContractAddress, u256>,
        allowances: Map<(ContractAddress, ContractAddress), u256>,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {}

    #[abi(embed_v0)]
    impl MockERC20Impl of IMockERC20<ContractState> {
        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.balances.read(account)
        }

        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            self.allowances.write((get_caller_address(), spender), amount);
            true
        }

        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            let sender = get_caller_address();
            let sender_balance = self.balances.read(sender);
            assert(sender_balance >= amount, 'MOCK_BALANCE_LOW');
            self.balances.write(sender, sender_balance - amount);
            self.balances.write(recipient, self.balances.read(recipient) + amount);
            true
        }

        fn mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
            self.balances.write(recipient, self.balances.read(recipient) + amount);
        }

        fn allowance(
            self: @ContractState, owner: ContractAddress, spender: ContractAddress,
        ) -> u256 {
            self.allowances.read((owner, spender))
        }
    }
}

#[starknet::interface]
pub trait IMockGhostPosition<TContractState> {
    fn configure_borrow(ref self: TContractState, transferred_amount: u256, reported_amount: u256);
    fn configure_close(
        ref self: TContractState,
        transferred_collateral: u256,
        transferred_refund: u256,
        reported_collateral: u256,
        reported_refund: u256,
    );
    fn last_repay(self: @TContractState) -> u256;
}

#[starknet::contract]
pub mod MockGhostPosition {
    use ghostloop_contracts::authorization::Authorization;
    use ghostloop_contracts::ghost_position::IGhostPosition;
    use ghostloop_contracts::interfaces::{IERC20Dispatcher, IERC20DispatcherTrait, Position};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_caller_address};
    use super::IMockGhostPosition;

    #[storage]
    struct Storage {
        anonymizer: ContractAddress,
        capability_public_key: felt252,
        eth: ContractAddress,
        usdc: ContractAddress,
        transferred_borrow: u256,
        reported_borrow: u256,
        transferred_collateral: u256,
        transferred_refund: u256,
        reported_collateral: u256,
        reported_refund: u256,
        last_repay: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        anonymizer: ContractAddress,
        capability_public_key: felt252,
        eth: ContractAddress,
        usdc: ContractAddress,
        _vesu_pool: ContractAddress,
        _vesu_multiply: ContractAddress,
    ) {
        self.anonymizer.write(anonymizer);
        self.capability_public_key.write(capability_public_key);
        self.eth.write(eth);
        self.usdc.write(usdc);
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn assert_anonymizer(self: @ContractState) {
            assert(get_caller_address() == self.anonymizer.read(), 'MOCK_BAD_CALLER');
        }

        fn transfer(
            self: @ContractState, token: ContractAddress, recipient: ContractAddress, amount: u256,
        ) {
            if amount != 0 {
                assert(
                    IERC20Dispatcher { contract_address: token }.transfer(recipient, amount),
                    'MOCK_XFER_FAILED',
                );
            }
        }
    }

    #[abi(embed_v0)]
    impl MockGhostPositionImpl of IMockGhostPosition<ContractState> {
        fn configure_borrow(
            ref self: ContractState, transferred_amount: u256, reported_amount: u256,
        ) {
            self.transferred_borrow.write(transferred_amount);
            self.reported_borrow.write(reported_amount);
        }

        fn configure_close(
            ref self: ContractState,
            transferred_collateral: u256,
            transferred_refund: u256,
            reported_collateral: u256,
            reported_refund: u256,
        ) {
            self.transferred_collateral.write(transferred_collateral);
            self.transferred_refund.write(transferred_refund);
            self.reported_collateral.write(reported_collateral);
            self.reported_refund.write(reported_refund);
        }

        fn last_repay(self: @ContractState) -> u256 {
            self.last_repay.read()
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
            let _ = (collateral_amount, debt_amount, minimum_borrowed, authorization);
            self.assert_anonymizer();
            self.transfer(self.usdc.read(), self.anonymizer.read(), self.transferred_borrow.read());
            self.reported_borrow.read()
        }

        fn repay(ref self: ContractState, repay_amount: u256, authorization: Authorization) {
            let _ = authorization;
            self.assert_anonymizer();
            self.last_repay.write(repay_amount);
        }

        fn close_borrow(
            ref self: ContractState, maximum_debt_input: u256, authorization: Authorization,
        ) -> (u256, u256) {
            let _ = (maximum_debt_input, authorization);
            self.assert_anonymizer();
            self
                .transfer(
                    self.eth.read(), self.anonymizer.read(), self.transferred_collateral.read(),
                );
            self.transfer(self.usdc.read(), self.anonymizer.read(), self.transferred_refund.read());
            (self.reported_collateral.read(), self.reported_refund.read())
        }

        fn increase_leverage(
            ref self: ContractState,
            add_margin: u256,
            debt_amount: u128,
            minimum_lever_collateral: u128,
            authorization: Authorization,
        ) -> (u256, u256) {
            let _ = (add_margin, debt_amount, minimum_lever_collateral, authorization);
            self.assert_anonymizer();
            (0, 0)
        }

        fn unwind(
            ref self: ContractState,
            maximum_collateral_swap: u128,
            minimum_collateral_returned: u256,
            authorization: Authorization,
        ) -> u256 {
            let _ = (maximum_collateral_swap, minimum_collateral_returned, authorization);
            self.assert_anonymizer();
            self
                .transfer(
                    self.eth.read(), self.anonymizer.read(), self.transferred_collateral.read(),
                );
            self.reported_collateral.read()
        }

        fn read_position(self: @ContractState) -> (Position, u256, u256) {
            (Position { collateral_shares: 0, nominal_debt: 0 }, 0, 0)
        }

        fn capability_public_key(self: @ContractState) -> felt252 {
            self.capability_public_key.read()
        }

        fn next_nonce(self: @ContractState) -> u64 {
            0
        }

        fn anonymizer(self: @ContractState) -> ContractAddress {
            self.anonymizer.read()
        }
    }
}
