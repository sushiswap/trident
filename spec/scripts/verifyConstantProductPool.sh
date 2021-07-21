# Use this run script to verify the ConstantProductPool.spec
certoraRun spec/harness/ConstantProductPoolHarness.sol spec/harness/SimpleBentoBox.sol spec/harness/Simplifications.sol \
	--verify ConstantProductPoolHarness:spec/ConstantProductPool.spec \
	--link ConstantProductPoolHarness:bento=SimpleBentoBox \
	--solc_map ConstantProductPoolHarness=solc8.2,SimpleBentoBox=solc6.12,Simplifications=solc8.2 \
	--optimistic_loop --loop_iter 2 \
    --packages @openzeppelin=/Users/vasu/Documents/Certora/trident/node_modules/@openzeppelin \
	--staging --msg "ConstantProductPool Pool"