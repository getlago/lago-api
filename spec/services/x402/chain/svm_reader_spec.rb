# frozen_string_literal: true

require "rails_helper"

describe X402::Chain::SvmReader do
  include SolanaTransactionBuilder

  subject(:reader) { described_class.new(network: "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1", payment:, payment_requirements: {}, since:) }

  let(:landed) { JSON.parse(File.read(Rails.root.join("spec/fixtures/x402/chain/solana_devnet_transfer.json"))) }
  let(:landed_bytes) { Base64.strict_decode64(landed["transaction"].first) }
  let(:transaction_id) { "7scJSNzkdyryaFQcfRX52upVRridoUijgMNaUmLBtJTxB9iCjmEDk2Mk54eEuTYoPqAgdtajPvxDMk9RFimsZ93" }
  let(:signed_by_buyer) { landed_bytes.dup.tap { |bytes| bytes[1, 64] = "\x00".b * 64 } }
  let(:payment) { {"x402Version" => 2, "payload" => {"transaction" => Base64.strict_encode64(signed_by_buyer)}} }
  let(:buyer) { "BprZ3eTVMHAcqC2wcE4XY71tvjdxJ6C6pSYjVmD75ujf" }
  let(:since) { Time.zone.at(landed["blockTime"] - 5) }

  let(:blockhash_valid) { false }
  let(:context_slot) { landed["slot"] + 400 }
  let(:genesis_hash) { "EtWTRABZaYq6iMfeYKouRu166VU2xqa1wcWFFmQcPYDT" }
  let(:history) { [{"signature" => transaction_id, "slot" => landed["slot"], "err" => nil, "blockTime" => landed["blockTime"]}] }
  let(:transactions) { {transaction_id => landed} }
  let(:rpc_calls) { [] }

  before do
    stub_request(:post, "https://api.devnet.solana.com").to_return do |request|
      rpc = JSON.parse(request.body)
      rpc_calls << rpc
      result = case rpc["method"]
      when "isBlockhashValid"
        {"context" => {"slot" => context_slot}, "value" => blockhash_valid}
      when "getSignaturesForAddress"
        before = rpc["params"].last["before"]
        start = before ? history.index { |entry| entry["signature"] == before } + 1 : 0
        history.drop(start).first(rpc["params"].last["limit"])
      when "getTransaction"
        transactions[rpc["params"].first]
      when "getBlockTime"
        slot_time(rpc["params"].first)
      when "getGenesisHash"
        genesis_hash
      end
      {status: 200, body: {jsonrpc: "2.0", id: 1, result:}.to_json}
    end
  end

  def calls(method)
    rpc_calls.select { |call| call["method"] == method }
  end

  def slot_time(slot)
    landed["blockTime"] + ((slot - landed["slot"]) * 2 / 5)
  end

  def other_entry(index, block_time: landed["blockTime"])
    {"signature" => X402::Base58.encode([index].pack("N").b * 16), "slot" => landed["slot"] - index, "err" => nil, "blockTime" => block_time}
  end

  def other_transaction
    signature = OpenSSL::Random.random_bytes(64)
    bytes = build_solana_transaction(keys: [buyer, SolanaTransactionBuilder::TOKEN_PROGRAM], instructions: [], signatures: [signature])
    landed.merge("transaction" => [Base64.strict_encode64(bytes), "base64"])
  end

  context "when the buyer's transaction landed" do
    it "is settled" do
      expect(reader.settled?).to be(true)
    end

    it "identifies the transaction by its id, the fee payer's signature" do
      expect(reader.identifier).to eq(transaction_id)
    end

    it "is final" do
      expect(reader.final?).to be(true)
    end

    it "scans the buyer's address, pinned to the expiry check's slot" do
      reader.settled?

      expect(calls("getSignaturesForAddress").sole["params"]).to eq([buyer, {"limit" => 1000, "commitment" => "finalized", "minContextSlot" => context_slot}])
    end

    it "checks the transaction's own blockhash" do
      reader.settled?

      expect(calls("isBlockhashValid").sole["params"]).to eq(["7LPzenu2Lg6XG5aSrZ6ihu7GFy9gHYEh5KVpVVxrQYue", {"commitment" => "finalized"}])
    end

    it "reads each fact once" do
      2.times { [reader.settled?, reader.identifier, reader.final?] }

      expect(calls("getTransaction").size).to eq(1)
    end
  end

  context "when other transactions of the buyer come first" do
    let(:history) { [other_entry(1), other_entry(2), super().first] }
    let(:transactions) { super().merge(history[0]["signature"] => other_transaction, history[1]["signature"] => other_transaction) }

    it "matches on the buyer's signature" do
      expect(reader.identifier).to eq(transaction_id)
    end
  end

  context "when the buyer's transaction did not land" do
    let(:history) { [] }

    it "is not settled" do
      expect(reader.settled?).to be(false)
    end

    it "has no identifier" do
      expect(reader.identifier).to be_nil
    end

    it "is final once the blockhash has expired" do
      expect(reader.final?).to be(true)
    end

    it "dates the expiry once" do
      2.times { reader.final? }

      expect(calls("getBlockTime").size).to eq(1)
    end

    context "when the blockhash is still valid" do
      let(:blockhash_valid) { true }

      it "is not final" do
        expect(reader.final?).to be(false)
      end
    end
  end

  context "when the node's slot is not proven past the blockhash's life" do
    let(:history) { [] }
    let(:context_slot) { landed["slot"] - 50 }

    it "is not final" do
      expect(reader.final?).to be(false)
    end
  end

  context "when the node cannot date its slot" do
    let(:history) { [] }

    def slot_time(_slot)
      nil
    end

    it "is not final" do
      expect(reader.final?).to be(false)
    end
  end

  context "when the endpoint serves another cluster" do
    let(:genesis_hash) { "5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d" }

    it "is inconclusive" do
      expect { reader.settled? }.to raise_error(X402::Chain::InconclusiveError, /another cluster/)
    end
  end

  context "when the cluster's block time runs minutes behind" do
    let(:history) { [super().first.merge("blockTime" => since.to_i - 300)] }

    it "still finds the transaction" do
      expect(reader.settled?).to be(true)
    end
  end

  context "when the buyer made thousands of later transactions" do
    let(:later) { Array.new(6_000) { |index| other_entry(index + 10, block_time: since.to_i + 3_600) } }
    let(:history) { later + super() }

    it "finds the transaction" do
      expect(reader.settled?).to be(true)
    end

    it "fetches only what could be the transaction" do
      reader.settled?

      expect(calls("getTransaction").size).to eq(1)
    end
  end

  context "when the buyer's transaction landed with an error" do
    let(:history) { [super().first.merge("err" => {"InstructionError" => [2, {"Custom" => 1}]})] }
    let(:transactions) { {transaction_id => landed.merge("meta" => {"err" => {"InstructionError" => [2, {"Custom" => 1}]}})} }

    it "is not settled" do
      expect(reader.settled?).to be(false)
    end

    it "is final, since that transaction can never land again" do
      expect(reader.final?).to be(true)
    end
  end

  context "when the endpoint returns the transaction with null metadata" do
    let(:history) { [super().first.merge("err" => {"InstructionError" => [2, {"Custom" => 1}]})] }
    let(:transactions) { {transaction_id => landed.merge("meta" => nil)} }

    it "is inconclusive" do
      expect { reader.settled? }.to raise_error(X402::Chain::InconclusiveError, /no status/)
    end
  end

  context "when the endpoint returns the transaction without metadata" do
    let(:transactions) { {transaction_id => landed.except("meta")} }

    it "is inconclusive" do
      expect { reader.settled? }.to raise_error(X402::Chain::InconclusiveError, /no status/)
    end
  end

  context "when the metadata has no error field" do
    let(:transactions) { {transaction_id => landed.merge("meta" => {})} }

    it "is inconclusive" do
      expect { reader.settled? }.to raise_error(X402::Chain::InconclusiveError, /no status/)
    end
  end

  context "when the history reaches back before the row was written" do
    let(:history) { [other_entry(1, block_time: since.to_i - 3_600), super().first] }

    it "stops scanning there" do
      expect(reader.settled?).to be(false)
    end
  end

  context "when a signature has no block time" do
    let(:history) { [other_entry(1, block_time: nil), super().first] }
    let(:transactions) { super().merge(history[0]["signature"] => other_transaction) }

    it "keeps scanning" do
      expect(reader.settled?).to be(true)
    end
  end

  context "when the history spans several pages" do
    let(:history) { Array.new(1_000) { |index| other_entry(index + 10) } + [super().first] }

    before do
      history.first(1_000).each { |entry| transactions[entry["signature"]] = other_transaction }
    end

    it "follows the before cursor" do
      expect(calls_after_settled("getSignaturesForAddress").last["params"].last["before"]).to eq(history[999]["signature"])
    end

    def calls_after_settled(method)
      reader.settled?
      calls(method)
    end
  end

  context "when the history is longer than the page cap" do
    let(:history) { Array.new(5_001) { |index| other_entry(index + 10) } }
    let(:transactions) { Hash.new { |hash, key| hash[key] = other_transaction } }

    it "is inconclusive" do
      expect { reader.settled? }.to raise_error(X402::Chain::InconclusiveError, /pages/)
    end
  end

  context "when even the later transactions exceed the total page cap" do
    let(:history) { Array.new(50_000) { |index| other_entry(index + 10, block_time: since.to_i + 3_600) } }

    it "is inconclusive" do
      expect { reader.settled? }.to raise_error(X402::Chain::InconclusiveError, /50 pages/)
    end
  end

  context "when the endpoint does not return a listed transaction" do
    let(:transactions) { {} }

    it "is inconclusive" do
      expect { reader.settled? }.to raise_error(X402::Chain::InconclusiveError, /getTransaction/)
    end
  end

  context "when the endpoint is unreachable" do
    before { stub_request(:post, "https://api.devnet.solana.com").to_raise(Errno::ECONNREFUSED) }

    it "raises instead of reading false" do
      expect { reader.settled? }.to raise_error(X402::Chain::UnreachableError)
    end
  end

  context "when the transaction uses a durable nonce" do
    let(:signed_by_buyer) do
      build_solana_transaction(
        keys: ["D6ZhtNQ5nT9ZnTHUbqXZsTx5MH2rPFiBBggX4hY1WePM", buyer, SolanaTransactionBuilder::SYSTEM_PROGRAM, SolanaTransactionBuilder::TOKEN_PROGRAM],
        instructions: [{program: 2, accounts: [1, 0, 1], data: [4].pack("L<")}, {program: 3, accounts: [1, 1, 1, 1], data: transfer_checked_data(1000)}],
        signatures: ["\x00".b * 64, "\x02".b * 64]
      )
    end

    it "raises, since it would never expire" do
      expect { reader.settled? }.to raise_error(X402::Chain::UnreadablePaymentError, /durable nonce/)
    end
  end

  context "when the transaction has no TransferChecked" do
    let(:signed_by_buyer) { build_solana_transaction(keys: [buyer], instructions: [], signatures: ["\x02".b * 64]) }

    it "raises" do
      expect { reader.settled? }.to raise_error(X402::Chain::UnreadablePaymentError, /TransferChecked/)
    end
  end

  context "when the authority does not sign" do
    let(:signed_by_buyer) do
      build_solana_transaction(
        keys: ["D6ZhtNQ5nT9ZnTHUbqXZsTx5MH2rPFiBBggX4hY1WePM", buyer, SolanaTransactionBuilder::TOKEN_PROGRAM],
        instructions: [{program: 2, accounts: [1, 1, 1, 1], data: transfer_checked_data(1000)}],
        signatures: ["\x00".b * 64]
      )
    end

    it "raises" do
      expect { reader.settled? }.to raise_error(X402::Chain::UnreadablePaymentError, /signer/)
    end
  end

  context "when the transaction is not base64" do
    let(:payment) { {"payload" => {"transaction" => "not base64!"}} }

    it "raises" do
      expect { reader.settled? }.to raise_error(X402::Chain::UnreadablePaymentError)
    end
  end
end
