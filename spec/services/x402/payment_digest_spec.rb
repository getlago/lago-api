# frozen_string_literal: true

require "rails_helper"

RSpec.describe X402::PaymentDigest do
  subject(:digest) { described_class.evm(network: "eip155:84532", asset: "0x036cbd53842c5426634e7929541ec2318f3dcf7e", authorization:) }

  let(:authorization) do
    {"from" => "0xfb6916095ca1df60bb79ce92ce3ea74c37c5d359", "to" => "0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed",
     "value" => "1000000", "validAfter" => "0", "validBefore" => "1790300000", "nonce" => "0x#{"CD" * 32}"}
  end

  # The same transfer spelled the way another client (or a checksumming middleware) would send it.
  let(:respelled_digest) do
    described_class.evm(network: "eip155:84532", asset: "0x036CbD53842c5426634e7929541eC2318f3dCF7e", authorization: {
      "from" => "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359", "to" => "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed",
      "value" => 1_000_000, "validAfter" => 0, "validBefore" => 1_790_300_000, "nonce" => "0x#{"cd" * 32}"
    })
  end

  it "keys on the transfer, not on its spelling" do
    expect(digest).to eq(respelled_digest)
  end
end
