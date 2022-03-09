import { BigNumber, utils } from "ethers";
import { keccak256 } from "@ethersproject/keccak256";
import { ecsign } from "ethereumjs-util";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BentoBoxV1 } from "../../types";

const BENTOBOX_MASTER_APPROVAL_TYPEHASH = keccak256(
  utils.toUtf8Bytes(
    "SetMasterContractApproval(string warning,address user,address masterContract,bool approved,uint256 nonce)"
  )
);

function getBentoBoxDomainSeparator(address, chainId) {
  return keccak256(
    utils.defaultAbiCoder.encode(
      ["bytes32", "bytes32", "uint256", "address"],
      [
        keccak256(utils.toUtf8Bytes("EIP712Domain(string name,uint256 chainId,address verifyingContract)")),
        keccak256(utils.toUtf8Bytes("BentoBox V1")),
        chainId,
        address,
      ]
    )
  );
}

function getBentoBoxApprovalDigest(bentoBox, user, masterContractAddress, approved, nonce, chainId = 1) {
  const DOMAIN_SEPARATOR = getBentoBoxDomainSeparator(bentoBox.address, chainId);
  const msg = utils.defaultAbiCoder.encode(
    ["bytes32", "bytes32", "address", "address", "bool", "uint256"],
    [
      BENTOBOX_MASTER_APPROVAL_TYPEHASH,
      approved
        ? keccak256(utils.toUtf8Bytes("Give FULL access to funds in (and approved to) BentoBox?"))
        : keccak256(utils.toUtf8Bytes("Revoke access to BentoBox?")),
      user.address,
      masterContractAddress,
      approved,
      nonce,
    ]
  );
  const pack = utils.solidityPack(
    ["bytes1", "bytes1", "bytes32", "bytes32"],
    ["0x19", "0x01", DOMAIN_SEPARATOR, keccak256(msg)]
  );
  return keccak256(pack);
}

export function getSignedMasterContractApprovalData(
  bentoBox: BentoBoxV1,
  user: SignerWithAddress,
  privateKey: string,
  masterContractAddress: string,
  approved: boolean,
  nonce: BigNumber,
  chainId: number
) {
  const digest = getBentoBoxApprovalDigest(bentoBox, user, masterContractAddress, approved, nonce, chainId);
  const { v, r, s } = ecsign(Buffer.from(digest.slice(2), "hex"), Buffer.from(privateKey.replace("0x", ""), "hex"));
  return { v, r, s };
}
