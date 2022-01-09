# Use this run script to verify the ConstantProductPool.spec
certoraRun spec/harness/ConstantProductPoolHarness.sol spec/harness/SimpleBentoBox.sol spec/harness/Simplifications.sol spec/harness/DummyERC20A.sol spec/harness/DummyERC20B.sol spec/harness/SymbolicTridentCallee.sol \
	--verify ConstantProductPoolHarness:spec/ConstantProductPool.spec \
	--link ConstantProductPoolHarness:bento=SimpleBentoBox SymbolicTridentCallee:bento=SimpleBentoBox \
	--solc_map ConstantProductPoolHarness=solc8.2,SymbolicTridentCallee=solc8.2,SimpleBentoBox=solc6.12,Simplifications=solc8.2,DummyERC20A=solc8.2,DummyERC20B=solc8.2 \
	--rule $1 --optimistic_loop --loop_iter 4 \
	--packages @openzeppelin=$PWD/node_modules/@openzeppelin \
	--javaArgs '"-Dcvt.default.parallelism=4"' \
	--staging --msg "ConstantProductPool: $1"

# --optimistic_loop --loop_iter 2