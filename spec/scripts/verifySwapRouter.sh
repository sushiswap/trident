certoraRun spec/harness/SwapRouterHarness.sol spec/harness/SimpleBentoBox.sol spec/harness/DummyERC20A.sol \
	--verify SwapRouterHarness:spec/SwapRouter.spec \
	--optimistic_loop --loop_iter 1 \
	--link SwapRouterHarness:bento=SimpleBentoBox \
	--packages @openzeppelin=$PWD/node_modules/@openzeppelin \
	--solc_map SwapRouterHarness=solc8.2,DummyERC20A=solc8.2,SimpleBentoBox=solc6.12 \
	--cache Trident \
	--staging --msg "Swap Router"
	#--packages @openzeppelin=/Users/vasu/Documents/Certora/trident/node_modules/@openzeppelin \