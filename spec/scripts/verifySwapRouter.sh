certoraRun spec/harness/SwapRouterHarness.sol \
	--verify SwapRouterHarness:spec/SwapRouter.spec \
	--optimistic_loop --loop_iter 2 \
    --packages @openzeppelin=/Users/vasu/Documents/Certora/trident/node_modules/@openzeppelin \
	--solc solc8.2 \
	--staging --msg "Swap Router"