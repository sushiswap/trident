certoraRun contracts/deployer/MasterDeployer.sol \
	--verify MasterDeployer:spec/sanity.spec \
	--optimistic_loop --loop_iter 2 \
	--packages @openzeppelin=/Users/nate/Documents/Projects/Sushi/trident/node_modules/@openzeppelin
	--staging --msg "Master Deployer"