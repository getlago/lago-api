# frozen_string_literal: true

RSpec.shared_context "with CDP credentials" do
  let(:cdp_host) { "https://api.cdp.coinbase.com" }
  let(:cdp_api_key_id) { "organizations/lago-test/apiKeys/x402" }
  let(:cdp_signing_key) { OpenSSL::PKey.generate_key("ED25519") }
  let(:cdp_api_key_secret) { Base64.strict_encode64(cdp_signing_key.raw_private_key + cdp_signing_key.raw_public_key) }

  def cdp_fixture(name)
    File.read(Rails.root.join("spec/fixtures/x402/cdp/#{name}.json"))
  end

  def cdp_account_url(family, address)
    "#{cdp_host}/platform/v2/#{(family == :svm) ? "solana" : "evm"}/accounts/#{address}"
  end

  def stub_cdp_supported(status: 200, body: cdp_fixture("supported"))
    stub_request(:get, "#{cdp_host}/platform/v2/x402/supported").to_return(status:, body:)
  end

  def stub_cdp_account(family, address, status: 200, body: cdp_account_body(address, status))
    stub_request(:get, cdp_account_url(family, address)).to_return(status:, body:)
  end

  def cdp_account_body(address, status)
    case status
    when 200 then {address:, name: "payout"}.to_json
    when 401 then "Unauthorized\n"
    when 404 then {errorType: "not_found", errorMessage: "Account with given address not found.", correlationId: "corr-404"}.to_json
    when 400 then {errorType: "invalid_request", correlationId: "corr-400"}.to_json
    else {errorType: "internal_server_error", correlationId: "corr-#{status}"}.to_json
    end
  end
end

RSpec.shared_context "with an x402 payment" do
  include_context "with CDP credentials"

  let(:organization) { create(:organization) }
  let(:x402_connection) do
    create(
      :x402_connection,
      organization:,
      networks: ["eip155:84532", "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1"],
      payout_addresses: {"evm" => "0x94bA479439C2f1bA5f5DaCBD06Ea0c129604B4a5", "svm" => "HHU1aLQQCbCzW9ebjFTntq2vkvsQsxkDyPjMsW2WtiLG"},
      cdp_api_key_id:,
      cdp_api_key_secret:
    )
  end
  let(:x402_svm_payer) { "BprZ3eTVMHAcqC2wcE4XY71tvjdxJ6C6pSYjVmD75ujf" }
  let(:cdp_facilitator_url) { "#{cdp_host}/platform/v2/x402" }

  let(:x402_evm_requirements) do
    {
      "scheme" => "exact",
      "network" => "eip155:84532",
      "amount" => "1000",
      "asset" => "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
      "payTo" => "0x94bA479439C2f1bA5f5DaCBD06Ea0c129604B4a5",
      "maxTimeoutSeconds" => 60,
      "extra" => {"name" => "USDC", "version" => "2"}
    }
  end
  let(:x402_evm_payment) do
    {
      "x402Version" => 2,
      "resource" => {"url" => "https://api.example.com/report", "description" => "Report", "mimeType" => "application/json"},
      "accepted" => x402_evm_requirements,
      "payload" => {
        "signature" => "0x#{"ab" * 65}",
        "authorization" => {
          "from" => "0xf4a43B9cc729c9E4E139CB86808f48e3eD09Dcb2",
          "to" => "0x94bA479439C2f1bA5f5DaCBD06Ea0c129604B4a5",
          "value" => "1000",
          "validAfter" => "1789648671",
          "validBefore" => "1789649331",
          "nonce" => "0x8568d530303a96028f64623cfc5c7bbb166c4aa2889b25bbe09e1d699193f174"
        }
      },
      "extensions" => {}
    }
  end

  let(:x402_svm_requirements) do
    {
      "scheme" => "exact",
      "network" => "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1",
      "amount" => "1000",
      "asset" => "4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU",
      "payTo" => "HHU1aLQQCbCzW9ebjFTntq2vkvsQsxkDyPjMsW2WtiLG",
      "maxTimeoutSeconds" => 60,
      "extra" => {"feePayer" => "GVJJ7rdGiXr5xaYbRwRbjfaJL7fmwRygFi1H6aGqDveb"}
    }
  end
  let(:x402_svm_payment) do
    landed = JSON.parse(File.read(Rails.root.join("spec/fixtures/x402/chain/solana_devnet_transfer.json")))
    bytes = Base64.strict_decode64(landed["transaction"].first)
    bytes[1, 64] = "\x00".b * 64

    {"x402Version" => 2, "accepted" => x402_svm_requirements, "payload" => {"transaction" => Base64.strict_encode64(bytes)}}
  end

  def stub_cdp_answer(path, status:, body:)
    stub_request(:post, "#{cdp_facilitator_url}#{path}").to_return(status:, body: body.is_a?(String) ? body : body.to_json)
  end

  def stub_cdp_facilitator(fault: nil)
    verify = {status: 200, body: cdp_fixture("verify_valid")}
    settle = {status: 200, body: cdp_fixture("settle_success")}
    transaction = "0x#{"cd" * 32}"

    case fault
    when :verify_reject
      verify = {status: 200, body: {isValid: false, invalidReason: "invalid_exact_evm_payload_signature", payer: "0xf4a43B9cc729c9E4E139CB86808f48e3eD09Dcb2"}.to_json}
    when :settle_fail_after_verify
      settle = {status: 400, body: {success: false, errorReason: "invalid_exact_evm_signature", network: "eip155:84532"}.to_json}
    when :settle_failed_onchain
      settle = {status: 400, body: {success: false, errorReason: "settle_exact_failed_onchain", network: "eip155:84532", transaction:}.to_json}
    when :settlement_pending
      settle = {status: 500, body: {success: false, errorReason: "settlement_pending", network: "eip155:84532", transaction:}.to_json}
    when :verify_without_payer
      verify = {status: 200, body: {isValid: true}.to_json}
    when :verify_kyt_decline
      verify = {status: 403, body: {errorType: "kyt_risk_detected", errorMessage: "risk"}.to_json}
    when :settle_kyt_decline
      settle = {status: 403, body: {errorType: "kyt_risk_detected", errorMessage: "risk"}.to_json}
    when :settle_server_error
      settle = {status: 500, body: {errorType: "internal_server_error", errorMessage: "internal error", correlationId: "corr-1"}.to_json}
    end

    stub_request(:post, "#{cdp_facilitator_url}/verify").to_return(verify)
    if fault == :settle_timeout
      stub_request(:post, "#{cdp_facilitator_url}/settle").to_raise(Net::ReadTimeout)
    elsif fault == :settle_dropped
      stub_request(:post, "#{cdp_facilitator_url}/settle").to_raise(Errno::ECONNRESET)
    else
      stub_request(:post, "#{cdp_facilitator_url}/settle").to_return(settle)
    end
    stub_cdp_supported
  end
end
