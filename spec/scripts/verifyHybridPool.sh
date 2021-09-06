# Use this run script to verify the HybridPool.spec
certoraRun spec/harness/HybridPoolHarness.sol spec/harness/SimpleBentoBox.sol spec/harness/Simplifications.sol spec/harness/DummyERC20A.sol spec/harness/DummyERC20B.sol \
	--verify HybridPoolHarness:spec/HybridPool.spec \
	--link HybridPoolHarness:bento=SimpleBentoBox \
	--solc_map HybridPoolHarness=solc8.2,SimpleBentoBox=solc6.12,Simplifications=solc8.2,DummyERC20A=solc8.2,DummyERC20B=solc8.2 \
	--rule $1 --optimistic_loop --loop_iter 4 \
    --packages @openzeppelin=$PWD/node_modules/@openzeppelin \
	--staging --msg "HybridPool: $1"