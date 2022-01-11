import { task, subtask } from "hardhat/config";

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of signers", async (args, { ethers: { getSigners } }) => {
  const accounts = await getSigners();

  for (const account of accounts) {
    console.log(await account.address);
  }
});

task("accounts:named", "Prints the list of named accounts", async (args, { ethers: { getNamedSigners } }) => {
  const accounts = await getNamedSigners();

  for (const [name, account] of Object.entries(accounts)) {
    console.log(`${name}: ${account.address}`);
  }
});
