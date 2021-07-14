certoraRun contracts/pool/HybridPool.sol spec/harness/SimpleBentoBox.sol \
	--verify HybridPool:spec/sanity.spec \
	--link HybridPool:bento=SimpleBentoBox \
	--solc_map HybridPool=solc8.2,SimpleBentoBox=solc6.12 \
	--optimistic_loop --loop_iter 2 \
	--packages @openzeppelin=/Users/nate/Documents/Projects/Sushi/trident/node_modules/@openzeppelin
	--staging --msg "Hybrid Pool"