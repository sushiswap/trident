# Use this run script to run the ConstantProductPool.spec
certoraRun contracts/pool/ConstantProductPool.sol spec/harness/SimpleBentoBox.sol spec/harness/Simplifications.sol \
	--verify ConstantProductPool:spec/ConstantProductPool.spec \
	--link ConstantProductPool:bento=SimpleBentoBox \
	--solc_map ConstantProductPool=solc8.2,SimpleBentoBox=solc6.12,Simplifications=solc8.2 \
	--optimistic_loop --loop_iter 2 \
    --packages @openzeppelin=/Users/vasu/Documents/Certora/trident/node_modules/@openzeppelin \
	--staging --msg "ConstantProductPool Pool"