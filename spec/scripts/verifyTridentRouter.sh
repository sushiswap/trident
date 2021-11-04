certoraRun spec/harness/TridentRouterHarness.sol spec/harness/SimpleBentoBox.sol spec/harness/DummyERC20A.sol spec/harness/DummyERC20B.sol spec/harness/DummyWeth.sol    spec/harness/Receiver.sol spec/harness/SymbolicPool.sol contracts/deployer/MasterDeployer.sol \
	--verify TridentRouterHarness:spec/TridentRouter.spec \
	--optimistic_loop --loop_iter 2 \
	--link TridentRouterHarness:bento=SimpleBentoBox SymbolicPool:bento=SimpleBentoBox SimpleBentoBox:wethToken=DummyWeth TridentRouterHarness:wETH=DummyWeth \
	--packages @openzeppelin=$PWD/node_modules/@openzeppelin \
	--solc_map MasterDeployer=solc8.0,TridentRouterHarness=solc8.2,DummyERC20A=solc8.2,SimpleBentoBox=solc6.12,SymbolicPool=solc8.2,DummyERC20B=solc8.2,Receiver=solc8.2,DummyWeth=solc8.2 \
	--settings -smt_hashingScheme=Legacy,-ignoreViewFunctions,-postProcessCounterExamples=true,-solvers=z3,-t=600,-depth=12 \
	--cache Trident --short_output \
	--rule $1 \
	--javaArgs '"-Dcvt.default.parallelism=4"' \
	--staging \
	--msg "Trident Router"\


