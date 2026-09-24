# frozen_string_literal: true

RSpec.shared_context "with an x402 payment" do
  let(:connection) { create(:x402_connection, organization:) }
  let(:agent_address) { "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359" }
  let(:amount_atomic) { "1000000" }
  let(:settle_tx_hash) { "0x3b1d6c2a9e0f4b5d8c7a6e1f2d3c4b5a69788796a5b4c3d2e1f0a9b8c7d6e5f4" }
  let(:verify_url) { "https://api.cdp.coinbase.com/platform/v2/x402/verify" }
  let(:settle_url) { "https://api.cdp.coinbase.com/platform/v2/x402/settle" }
  let(:payment_requirements) do
    {
      "scheme" => "exact",
      "network" => "eip155:84532",
      "amount" => amount_atomic,
      "asset" => "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
      "payTo" => "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed",
      "maxTimeoutSeconds" => 60,
      "extra" => {"name" => "USDC", "version" => "2"}
    }
  end
  # The agent signs lowercase addresses: E8 must still resolve one checksummed customer (review focus 1).
  let(:payment) do
    {
      "x402Version" => 2,
      "accepted" => payment_requirements,
      "payload" => {
        "signature" => "0x#{"ab" * 65}",
        "authorization" => {
          "from" => agent_address.downcase,
          "to" => "0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed",
          "value" => amount_atomic,
          "validAfter" => "0",
          "validBefore" => 60.seconds.from_now.to_i.to_s,
          "nonce" => "0x#{"cd" * 32}"
        }
      }
    }
  end

  before do
    stub_request(:post, verify_url).to_return(status: 200, body: File.read(Rails.root.join("spec/fixtures/x402/cdp/verify_valid.json")))
    stub_request(:post, settle_url).to_return(status: 200, body: File.read(Rails.root.join("spec/fixtures/x402/cdp/settle_success.json")))
  end
end
