# frozen_string_literal: true

require "rails_helper"

describe X402::Chain::EvmReader do
  subject(:reader) { described_class.new(network: "eip155:84532", payment:, payment_requirements:, since:) }

  let(:chain_data) { JSON.parse(File.read(Rails.root.join("spec/fixtures/x402/chain/base_sepolia_authorization_used.json"))) }
  let(:log) { chain_data["log"] }
  let(:receipt) { chain_data["receipt"] }
  let(:log_block) { log["blockNumber"].to_i(16) }
  let(:log_time) { 1_789_649_274 }

  let(:asset) { "0x036CbD53842c5426634e7929541eC2318f3dCF7e" }
  let(:valid_before) { 1_789_649_331 }
  let(:authorization) do
    {
      "from" => "0xf4a43B9cc729c9E4E139CB86808f48e3eD09Dcb2",
      "to" => "0x94bA479439C2f1bA5f5DaCBD06Ea0c129604B4a5",
      "value" => "1000",
      "validAfter" => (valid_before - 660).to_s,
      "validBefore" => valid_before.to_s,
      "nonce" => "0x8568d530303a96028f64623cfc5c7bbb166c4aa2889b25bbe09e1d699193f174"
    }
  end
  let(:payment) { {"x402Version" => 2, "payload" => {"signature" => "0x00", "authorization" => authorization}} }
  let(:payment_requirements) { {"scheme" => "exact", "network" => "eip155:84532", "asset" => asset} }
  let(:since) { Time.zone.at(log_time - 4) }

  let(:safe_block) { log_block + 90 }
  let(:authorization_used) { true }
  let(:logs) { [log] }
  let(:rpc_calls) { [] }
  let(:chain_id) { "0x14a34" }

  def block_time(number)
    log_time + (2 * (number - log_block))
  end

  before do
    stub_request(:post, "https://sepolia.base.org").to_return do |request|
      rpc = JSON.parse(request.body)
      rpc_calls << rpc
      result = case rpc["method"]
      when "eth_chainId"
        chain_id
      when "eth_getBlockByNumber"
        number = {"safe" => safe_block}.fetch(rpc["params"].first) { |tag| tag.to_i(16) }
        {"number" => "0x#{number.to_s(16)}", "timestamp" => "0x#{block_time(number).to_s(16)}"}
      when "eth_call"
        "0x#{((authorization_used && rpc["params"].last.to_i(16) >= log_block) ? 1 : 0).to_s.rjust(64, "0")}"
      when "eth_getLogs"
        from, to = rpc["params"].first.values_at("fromBlock", "toBlock").map { |block| block.to_i(16) }
        logs.select { |entry| (from..to).cover?(entry["blockNumber"].to_i(16)) }
      when "eth_getTransactionReceipt"
        receipt
      end
      {status: 200, body: {jsonrpc: "2.0", id: 1, result:}.to_json}
    end
  end

  def calls(method)
    rpc_calls.select { |call| call["method"] == method }
  end

  context "when the authorization paid the payee" do
    it "is settled" do
      expect(reader.settled?).to be(true)
    end

    it "identifies the transaction from the chain" do
      expect(reader.identifier).to eq("0xefad33f01282b3a8b18893a9eb0aecbc2fc210ffcfa7fda7ca79f14c8822963a")
    end

    it "is final" do
      expect(reader.final?).to be(true)
    end

    it "asks the asset contract, at the safe block it read" do
      reader.settled?

      expect(calls("eth_call").sole["params"]).to eq([
        {"to" => asset, "data" => "0xe94a0102#{"f4a43b9cc729c9e4e139cb86808f48e3ed09dcb2".rjust(64, "0")}8568d530303a96028f64623cfc5c7bbb166c4aa2889b25bbe09e1d699193f174"},
        "0x#{safe_block.to_s(16)}"
      ])
    end

    it "filters the logs by contract, authorizer and nonce" do
      reader.settled?

      expect(calls("eth_getLogs").first["params"].first).to include(
        "address" => asset,
        "topics" => [
          %w[0x98de503528ee59b575ef0c0a2576a82497bfc029a5685b209e9ec333479b10a5 0x1cdd46ff242716cdaa72d159d339a485b3438398348d68f09d7c8c0a59353d81],
          "0x#{"f4a43b9cc729c9e4e139cb86808f48e3ed09dcb2".rjust(64, "0")}",
          "0x8568d530303a96028f64623cfc5c7bbb166c4aa2889b25bbe09e1d699193f174"
        ]
      )
    end

    it "reads each fact once" do
      2.times { [reader.settled?, reader.identifier, reader.final?] }

      expect(calls("eth_call").size).to eq(1)
    end
  end

  context "when the settle answer named another hash" do
    let(:payment) { super().merge("settleResponse" => {"transaction" => "0x#{"99" * 32}"}) }

    it "identifies the chain's transaction" do
      expect(reader.identifier).to eq(log["transactionHash"])
    end
  end

  context "when the authorization is unused" do
    let(:authorization_used) { false }

    it "is not settled" do
      expect(reader.settled?).to be(false)
    end

    it "has no identifier" do
      expect(reader.identifier).to be_nil
    end

    it "is final once the safe block is past validBefore" do
      expect(reader.final?).to be(true)
    end

    it "reads only the safe block" do
      reader.final?

      expect(calls("eth_getBlockByNumber").map { |call| call["params"].first }).to eq(["safe"])
    end

    context "when the safe block is still before validBefore" do
      let(:safe_block) { log_block + 10 }

      it "is not final" do
        expect(reader.final?).to be(false)
      end
    end
  end

  context "when the payment's block is not yet safe" do
    let(:safe_block) { log_block - 1 }

    it "is not settled" do
      expect(reader.settled?).to be(false)
    end

    it "has no identifier" do
      expect(reader.identifier).to be_nil
    end

    it "is not final" do
      expect(reader.final?).to be(false)
    end

    it "reads no receipt" do
      reader.settled?

      expect(calls("eth_getTransactionReceipt")).to be_empty
    end

    context "when that block holds a cancellation" do
      let(:logs) { [log.merge("topics" => ["0x1cdd46ff242716cdaa72d159d339a485b3438398348d68f09d7c8c0a59353d81", *log["topics"].drop(1)])] }

      it "is not final" do
        expect(reader.final?).to be(false)
      end
    end
  end

  context "when the log's block is the safe block" do
    let(:safe_block) { log_block }

    it "is settled" do
      expect(reader.settled?).to be(true)
    end
  end

  context "when the endpoint has no safe block" do
    before do
      stub_request(:post, "https://sepolia.base.org").with { |request| JSON.parse(request.body)["params"] == ["safe", false] }
        .to_return(status: 200, body: {jsonrpc: "2.0", id: 1, result: nil}.to_json)
    end

    it "is inconclusive" do
      expect { reader.settled? }.to raise_error(X402::Chain::InconclusiveError, /no safe block/)
    end
  end

  context "when the safe block has no number" do
    before do
      stub_request(:post, "https://sepolia.base.org").with { |request| JSON.parse(request.body)["params"] == ["safe", false] }
        .to_return(status: 200, body: {jsonrpc: "2.0", id: 1, result: {"timestamp" => "0x1"}}.to_json)
    end

    it "is inconclusive" do
      expect { reader.settled? }.to raise_error(X402::Chain::InconclusiveError, /no safe block/)
    end
  end

  context "when eth_getLogs answers something other than a list" do
    before do
      stub_request(:post, "https://sepolia.base.org").with { |request| JSON.parse(request.body)["method"] == "eth_getLogs" }
        .to_return(status: 200, body: {jsonrpc: "2.0", id: 1, result: {"logs" => []}}.to_json)
    end

    it "is inconclusive" do
      expect { reader.settled? }.to raise_error(X402::Chain::InconclusiveError, /eth_getLogs/)
    end
  end

  context "when a log carries no topics" do
    let(:logs) { [log.except("topics")] }

    it "is inconclusive" do
      expect { reader.settled? }.to raise_error(X402::Chain::InconclusiveError, /eth_getLogs/)
    end
  end

  context "when the receipt lists no logs" do
    let(:receipt) { chain_data["receipt"].except("logs") }

    it "is inconclusive" do
      expect { reader.settled? }.to raise_error(X402::Chain::InconclusiveError, /receipt/)
    end
  end

  context "when the authorization was canceled" do
    let(:logs) { [log.merge("topics" => ["0x1cdd46ff242716cdaa72d159d339a485b3438398348d68f09d7c8c0a59353d81", *log["topics"].drop(1)])] }

    it "is not settled" do
      expect(reader.settled?).to be(false)
    end

    it "is final" do
      expect(reader.final?).to be(true)
    end
  end

  [300, 1_000].each do |offset|
    context "when the buyer canceled #{offset} blocks after the payment's block" do
      let(:safe_block) { log_block + 5_000 }
      let(:logs) { [log.merge("blockNumber" => "0x#{(log_block + offset).to_s(16)}", "topics" => ["0x1cdd46ff242716cdaa72d159d339a485b3438398348d68f09d7c8c0a59353d81", *log["topics"].drop(1)])] }

      it "is not settled" do
        expect(reader.settled?).to be(false)
      end

      it "is final" do
        expect(reader.final?).to be(true)
      end

      it "looks only for cancellations past the window" do
        reader.settled?

        expect(calls("eth_getLogs").last["params"].first["topics"].first).to eq(["0x1cdd46ff242716cdaa72d159d339a485b3438398348d68f09d7c8c0a59353d81"])
      end
    end
  end

  context "when the nonce paid someone else" do
    let(:receipt) do
      transfer = chain_data["receipt"]["logs"].last
      chain_data["receipt"].merge("logs" => [chain_data["receipt"]["logs"].first, transfer.merge("topics" => [*transfer["topics"].first(2), "0x#{"11" * 32}"])])
    end

    it "is not settled" do
      expect(reader.settled?).to be(false)
    end

    it "is final" do
      expect(reader.final?).to be(true)
    end
  end

  context "when the transfer's amount differs" do
    let(:receipt) do
      logs = chain_data["receipt"]["logs"]
      chain_data["receipt"].merge("logs" => [logs.first, logs.last.merge("data" => "0x#{"1".rjust(64, "0")}")])
    end

    it "is not settled" do
      expect(reader.settled?).to be(false)
    end
  end

  context "when the transaction failed" do
    let(:receipt) { chain_data["receipt"].merge("status" => "0x0") }

    it "is inconclusive" do
      expect { reader.settled? }.to raise_error(X402::Chain::InconclusiveError)
    end
  end

  context "when the nonce is used but no event is found" do
    let(:logs) { [] }

    it "is inconclusive" do
      expect { reader.settled? }.to raise_error(X402::Chain::InconclusiveError, /no AuthorizationUsed/)
    end
  end

  context "when eth_call answers an empty result" do
    before do
      stub_request(:post, "https://sepolia.base.org").with { |request| JSON.parse(request.body)["method"] == "eth_call" }
        .to_return(status: 200, body: {jsonrpc: "2.0", id: 1, result: "0x"}.to_json)
    end

    it "is inconclusive" do
      expect { reader.settled? }.to raise_error(X402::Chain::InconclusiveError, /authorizationState/)
    end
  end

  context "when the row is read a day later" do
    let(:safe_block) { log_block + 43_200 }

    it "scans inclusive chunks of at most 1,000 blocks" do
      reader.settled?

      expect(calls("eth_getLogs").map { |call| call["params"].first.values_at("fromBlock", "toBlock").map { |block| block.to_i(16) } })
        .to all(satisfy { |from, to| to - from < 1_000 })
    end

    it "only scans the authorization's window" do
      reader.settled?

      expect(calls("eth_getLogs").size).to eq(1)
    end

    it "still finds the transaction" do
      expect(reader.identifier).to eq(log["transactionHash"])
    end
  end

  context "when blocks come slower than estimated" do
    def block_time(number)
      log_time + (3 * (number - log_block))
    end

    let(:safe_block) { log_block + 2_000 }

    it "widens the window to find the transaction" do
      expect(reader.identifier).to eq(log["transactionHash"])
    end
  end

  context "when blocks come faster than estimated" do
    def block_time(number)
      log_time + ((number - log_block) * 9 / 5)
    end

    let(:safe_block) { log_block + 2_000 }

    it "widens the window to find the transaction" do
      expect(reader.identifier).to eq(log["transactionHash"])
    end
  end

  context "when no block precedes the window" do
    def block_time(_number)
      log_time + 86_400
    end

    it "is inconclusive" do
      expect { reader.settled? }.to raise_error(X402::Chain::InconclusiveError, /could not find a block before/)
    end
  end

  context "when block times stall before validBefore" do
    def block_time(number)
      return log_time + (2 * (number - log_block)) if number < log_block || number == safe_block

      valid_before - 1
    end

    let(:safe_block) { log_block + 43_200 }

    it "scans up to the safe block" do
      expect(reader.identifier).to eq(log["transactionHash"])
    end
  end

  context "when the window would start before the first block" do
    let(:authorization) { super().merge("validAfter" => "0") }
    let(:since) { Time.zone.at(0) }
    let(:logs) { [] }

    it "starts at block 0" do
      expect { reader.settled? }.to raise_error(X402::Chain::InconclusiveError, /blocks 0\.\./)
    end

    it "says the scan stopped at its chunk cap" do
      expect { reader.settled? }.to raise_error(X402::Chain::InconclusiveError, /exceeds 50 chunks/)
    end
  end

  context "when a bound block is unknown to the endpoint" do
    before do
      stub_request(:post, "https://sepolia.base.org").with { |request| JSON.parse(request.body).then { |rpc| rpc["method"] == "eth_getBlockByNumber" && rpc["params"].first != "safe" } }
        .to_return(status: 200, body: {jsonrpc: "2.0", id: 1, result: nil}.to_json)
    end

    it "is inconclusive" do
      expect { reader.settled? }.to raise_error(X402::Chain::InconclusiveError, /unknown to the endpoint/)
    end
  end

  context "when the authorization carries numbers" do
    let(:authorization) { super().merge("value" => 1000, "validAfter" => valid_before - 660, "validBefore" => valid_before) }

    it "is settled" do
      expect(reader.settled?).to be(true)
    end
  end

  [-1, "1.5", nil].each do |bad_value|
    context "when the value is #{bad_value.inspect}" do
      let(:authorization) { super().merge("value" => bad_value) }

      it "raises" do
        expect { reader.settled? }.to raise_error(X402::Chain::UnreadablePaymentError)
      end
    end
  end

  context "without a since" do
    let(:since) { nil }

    it "raises" do
      expect { reader.settled? }.to raise_error(ArgumentError, /since/)
    end
  end

  context "when the endpoint serves another chain" do
    let(:chain_id) { "0x2105" }

    it "is inconclusive" do
      expect { reader.settled? }.to raise_error(X402::Chain::InconclusiveError, /another chain/)
    end
  end

  context "when the endpoint is unreachable" do
    before { stub_request(:post, "https://sepolia.base.org").to_raise(Net::ReadTimeout) }

    it "raises instead of reading false" do
      expect { reader.settled? }.to raise_error(X402::Chain::UnreachableError)
    end
  end

  context "when the authorization is malformed" do
    let(:authorization) { super().merge("nonce" => "0x1234") }

    it "raises" do
      expect { reader.settled? }.to raise_error(X402::Chain::UnreadablePaymentError)
    end
  end

  context "when the requirements name no contract" do
    let(:payment_requirements) { {"asset" => "USDC"} }

    it "raises" do
      expect { reader.settled? }.to raise_error(X402::Chain::UnreadablePaymentError)
    end
  end
end
