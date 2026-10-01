# frozen_string_literal: true

require "rails_helper"

describe X402::Connection do
  subject(:connection) { build(:x402_connection, networks:, payout_addresses:) }

  let(:networks) { ["eip155:84532"] }
  let(:payout_addresses) { {"evm" => evm_address} }
  let(:evm_address) { "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed" }
  let(:svm_address) { "2wKupLR9q6wXYppw8Gr2NvWxKBUqm4PPJKkQfoxHDBg4" }

  it { expect(described_class).to be_soft_deletable }

  describe "enums" do
    it do
      expect(connection).to define_enum_for(:facilitator)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(coinbase_cdp: "coinbase_cdp")
      expect(connection).to define_enum_for(:asset)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(usdc: "usdc")
    end
  end

  describe "associations" do
    it do
      expect(connection).to belong_to(:organization)
    end
  end

  describe "validations" do
    it do
      expect(connection).to validate_presence_of(:code)
      expect(connection).to validate_presence_of(:name)
      expect(connection).to validate_presence_of(:networks)
      expect(connection).to validate_presence_of(:secrets)
    end

    describe "code uniqueness" do
      let(:organization) { create(:organization) }
      let(:duplicate) { build(:x402_connection, organization:, code: "cdp") }

      context "when a kept connection of the organization holds the code" do
        before { create(:x402_connection, organization:, code: "cdp") }

        it "rejects the code" do
          expect(duplicate).not_to be_valid
          expect(duplicate.errors.where(:code, :taken)).to be_present
        end
      end

      context "when only a discarded connection holds the code" do
        before { create(:x402_connection, :discarded, organization:, code: "cdp") }

        it { expect(duplicate).to be_valid }
      end

      context "when another organization holds the code" do
        before { create(:x402_connection, code: "cdp") }

        it { expect(duplicate).to be_valid }
      end
    end

    describe "networks validation" do
      before { connection.valid? }

      context "with an unsupported network" do
        let(:networks) { ["eip155:1"] }

        it { expect(connection.errors.messages[:networks]).to eq(["value_is_invalid"]) }
      end

      context "with mainnet and testnet networks" do
        let(:networks) { ["eip155:8453", "eip155:84532"] }

        it { expect(connection.errors.messages[:networks]).to eq(["mixed_environments"]) }
      end

      context "with mainnet networks of both families" do
        let(:networks) { ["eip155:8453", "solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp"] }
        let(:payout_addresses) { {"evm" => evm_address, "svm" => svm_address} }

        it { expect(connection.errors).to be_empty }
      end

      context "without networks" do
        let(:networks) { nil }

        it { expect(connection.errors.messages[:networks]).to eq(["value_is_mandatory"]) }
      end
    end

    describe "payout_addresses validation" do
      before { connection.valid? }

      context "when an SVM network has only an EVM payout address" do
        let(:networks) { ["eip155:84532", "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1"] }

        it { expect(connection.errors.messages[:payout_addresses]).to eq(["missing_svm_payout_address"]) }
      end

      context "when an EVM network has only an SVM payout address" do
        let(:payout_addresses) { {"svm" => svm_address} }

        it { expect(connection.errors.messages[:payout_addresses]).to eq(["missing_evm_payout_address"]) }
      end

      context "with a mixed-case EVM address whose checksum is wrong" do
        let(:evm_address) { "0x5AAeb6053F3E94C9b9A09f33669435E7Ef1BeAed" }

        it { expect(connection.errors.messages[:payout_addresses]).to eq(["invalid_checksum"]) }
      end

      context "with a lowercase EVM address" do
        let(:evm_address) { "0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed" }

        it "stores the checksummed address" do
          expect(connection.errors).to be_empty
          expect(connection.payout_addresses).to eq("evm" => "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed")
        end
      end

      context "with an uppercase EVM address" do
        let(:evm_address) { "0x5AAEB6053F3E94C9B9A09F33669435E7EF1BEAED" }

        it { expect(connection.payout_addresses).to eq("evm" => "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed") }
      end

      context "with a truncated EVM address" do
        let(:evm_address) { "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeA" }

        it { expect(connection.errors.messages[:payout_addresses]).to eq(["invalid_format"]) }
      end

      context "with a transaction signature as the SVM address" do
        let(:networks) { ["solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1"] }
        let(:payout_addresses) { {"svm" => X402::Base58.encode("\x01".b * 64)} }

        it { expect(connection.errors.messages[:payout_addresses]).to eq(["invalid_format"]) }
      end

      context "with an unknown family" do
        let(:payout_addresses) { {"evm" => evm_address, "sui" => evm_address} }

        it { expect(connection.errors.messages[:payout_addresses]).to eq(["value_is_invalid"]) }
      end

      context "with payout addresses that are not an object" do
        let(:payout_addresses) { [evm_address] }

        it { expect(connection.errors.messages[:payout_addresses]).to eq(["value_is_invalid"]) }
      end

      context "without payout addresses" do
        let(:payout_addresses) { nil }

        it { expect(connection.errors.messages[:payout_addresses]).to eq(["value_is_invalid"]) }
      end

      context "with symbol keys" do
        let(:payout_addresses) { {evm: evm_address.downcase} }

        it "stores string keys and the checksummed address" do
          expect(connection.errors).to be_empty
          expect(connection.payout_addresses).to eq("evm" => evm_address)
        end
      end

      context "with an address for a family no network uses" do
        let(:payout_addresses) { {"evm" => evm_address, "svm" => svm_address} }

        it { expect(connection.errors).to be_empty }
      end
    end
  end

  describe "secrets" do
    let(:connection) { create(:x402_connection, cdp_api_key_id: "key-id", cdp_api_key_secret: "key-secret") }

    it "keeps the CDP key encrypted at rest" do
      expect(connection.reload.cdp_api_key_secret).to eq("key-secret")
      expect(connection.ciphertext_for(:secrets)).not_to include("key-secret")
    end
  end

  describe "unique code index" do
    subject(:insert) { duplicate.save(validate: false) }

    let(:organization) { create(:organization) }
    let(:duplicate) { build(:x402_connection, organization:, code: "cdp") }

    context "when a kept connection holds the code" do
      before { create(:x402_connection, organization:, code: "cdp") }

      it { expect { insert }.to raise_error(ActiveRecord::RecordNotUnique, /index_x402_connections_on_organization_id_and_code/) }
    end

    context "when a discarded connection holds the code" do
      before { create(:x402_connection, :discarded, organization:, code: "cdp") }

      it { expect(insert).to be(true) }
    end
  end
end
