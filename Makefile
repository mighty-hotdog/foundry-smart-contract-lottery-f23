-include .env

build:; forge build

deploy-sepolia:
	forge script script/DeployRaffle.s.sol:DeployRaffle --rpc-url $(SEPOLIA_ALCHEMY_RPC_URL) --account SEPOLIA_TESTNET_KEY --sender $(SEPOLIA_TESTNET_KEY_SENDER) --password-file $(PASSWORD_FILE) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY)

deploy-anvil:
	forge script script/DeployRaffle.s.sol:DeployRaffle --rpc-url $(DEFAULT_ANVIL_RPC_URL) --private-key $(DEFAULT_ANVIL_KEY) --broadcast