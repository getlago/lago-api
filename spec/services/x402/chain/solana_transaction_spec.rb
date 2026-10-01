# frozen_string_literal: true

require "rails_helper"

describe X402::Chain::SolanaTransaction do
  include SolanaTransactionBuilder

  subject(:transaction) { described_class.decode(bytes) }

  let(:landed) { JSON.parse(File.read(Rails.root.join("spec/fixtures/x402/chain/solana_devnet_transfer.json"))) }
  let(:bytes) { Base64.strict_decode64(landed["transaction"].first) }

  let(:fee_payer) { "D6ZhtNQ5nT9ZnTHUbqXZsTx5MH2rPFiBBggX4hY1WePM" }
  let(:buyer) { "BprZ3eTVMHAcqC2wcE4XY71tvjdxJ6C6pSYjVmD75ujf" }
  let(:merchant_token_account) { "H6KPkFCgvBzk6uCcD3VmQKZdp2BTkcoCctcgziSLeSpL" }

  describe ".decode" do
    it "reads the signatures" do
      expect(transaction.signatures.map { |signature| X402::Base58.encode(signature) }.first).to eq("7scJSNzkdyryaFQcfRX52upVRridoUijgMNaUmLBtJTxB9iCjmEDk2Mk54eEuTYoPqAgdtajPvxDMk9RFimsZ93")
    end

    it "reads a v0 message" do
      expect(transaction).to have_attributes(version: 0, num_required_signatures: 2, address_table_lookups: [])
    end

    it "reads the account keys" do
      expect(transaction.account_keys.first(2).map { |key| X402::Base58.encode(key) }).to eq([fee_payer, buyer])
    end

    it "reads the recent blockhash" do
      expect(X402::Base58.encode(transaction.recent_blockhash)).to eq("7LPzenu2Lg6XG5aSrZ6ihu7GFy9gHYEh5KVpVVxrQYue")
    end

    context "with a legacy message" do
      let(:bytes) do
        build_solana_transaction(
          keys: [fee_payer, buyer, SolanaTransactionBuilder::TOKEN_PROGRAM],
          instructions: [{program: 2, accounts: [1, 1, 1, 1], data: transfer_checked_data(5)}],
          signatures: ["\x01".b * 64, "\x02".b * 64],
          version: nil
        )
      end

      it "reads it" do
        expect(transaction).to have_attributes(version: :legacy, num_required_signatures: 2, address_table_lookups: [])
      end
    end

    context "with instruction data needing a two-byte length" do
      let(:bytes) do
        build_solana_transaction(
          keys: [fee_payer, SolanaTransactionBuilder::TOKEN_PROGRAM],
          instructions: [{program: 1, accounts: [0], data: "\x09".b * 200}],
          signatures: ["\x01".b * 64]
        )
      end

      it "reads the whole data" do
        expect(transaction.instructions.first.data.bytesize).to eq(200)
      end
    end

    context "with an address lookup table" do
      let(:bytes) do
        build_solana_transaction(
          keys: [fee_payer],
          instructions: [],
          signatures: ["\x01".b * 64],
          lookups: [{table: merchant_token_account, writable: [3], readonly: [1, 2]}]
        )
      end

      it "reads it" do
        expect(transaction.address_table_lookups).to eq([{account_key: X402::Base58.decode(merchant_token_account), writable_indexes: [3], readonly_indexes: [1, 2]}])
      end
    end

    context "when the bytes are truncated" do
      let(:bytes) { Base64.strict_decode64(landed["transaction"].first)[0, 300] }

      it "raises" do
        expect { transaction }.to raise_error(X402::Chain::UnreadablePaymentError, /truncated/)
      end
    end

    context "when a length prefix runs past three bytes" do
      let(:bytes) { compact_u16(1) + ("\x01".b * 64) + "\x80\x01\x00\x00\xff\xff\xff\x01".b }

      it "raises" do
        expect { transaction }.to raise_error(X402::Chain::UnreadablePaymentError, /compact-u16/)
      end
    end

    context "when the message is missing" do
      let(:bytes) { compact_u16(1) + ("\x01".b * 64) }

      it "raises" do
        expect { transaction }.to raise_error(X402::Chain::UnreadablePaymentError, /truncated/)
      end
    end

    context "when bytes are left over" do
      let(:bytes) { Base64.strict_decode64(landed["transaction"].first) + "\x00".b }

      it "raises" do
        expect { transaction }.to raise_error(X402::Chain::UnreadablePaymentError, /trailing/)
      end
    end

    context "with a v1 transaction" do
      let(:bytes) { "\x81\x01\x00\x00".b + ("\x00".b * 64) }

      it "raises" do
        expect { transaction }.to raise_error(X402::Chain::UnreadablePaymentError, /legacy and v0/)
      end
    end

    context "with a message version above 0" do
      let(:bytes) { build_solana_transaction(keys: [fee_payer], instructions: [], signatures: ["\x01".b * 64], version: 1) }

      it "raises" do
        expect { transaction }.to raise_error(X402::Chain::UnreadablePaymentError, /legacy and v0/)
      end
    end
  end

  describe "#transfer_checked" do
    it "finds the SPL Token transfer" do
      expect(transaction.transfer_checked).to have_attributes(accounts: [2, 4, 3, 1])
    end

    context "with a Token-2022 transfer" do
      let(:bytes) do
        build_solana_transaction(
          keys: [fee_payer, buyer, SolanaTransactionBuilder::TOKEN_2022_PROGRAM],
          instructions: [{program: 2, accounts: [1, 1, 1, 1], data: transfer_checked_data(5)}],
          signatures: ["\x01".b * 64, "\x02".b * 64]
        )
      end

      it "finds it" do
        expect(transaction.transfer_checked).to have_attributes(program_id_index: 2)
      end
    end

    context "without a transfer" do
      let(:bytes) do
        build_solana_transaction(keys: [fee_payer, SolanaTransactionBuilder::TOKEN_PROGRAM], instructions: [{program: 1, accounts: [0], data: "\x03".b}], signatures: ["\x01".b * 64])
      end

      it { expect(transaction.transfer_checked).to be_nil }
    end
  end

  describe "#signature_for" do
    it "returns the signature of a signer" do
      expect(transaction.signature_for(X402::Base58.decode(buyer))).to eq(transaction.signatures[1])
    end

    it "returns nil for a key that does not sign" do
      expect(transaction.signature_for(X402::Base58.decode(merchant_token_account))).to be_nil
    end
  end

  describe "#durable_nonce?" do
    it { expect(transaction.durable_nonce?).to be(false) }

    context "when the first instruction advances a nonce account" do
      let(:bytes) do
        build_solana_transaction(
          keys: [fee_payer, buyer, SolanaTransactionBuilder::SYSTEM_PROGRAM],
          instructions: [{program: 2, accounts: [1, 0, 1], data: [4].pack("L<")}],
          signatures: ["\x01".b * 64]
        )
      end

      it { expect(transaction.durable_nonce?).to be(true) }
    end
  end
end
