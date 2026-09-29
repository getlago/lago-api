# frozen_string_literal: true

require "rails_helper"

describe X402::Network do
  let(:solana_address) { "2wKupLR9q6wXYppw8Gr2NvWxKBUqm4PPJKkQfoxHDBg4" }

  describe ".family_of_network" do
    subject(:family) { described_class.family_of_network(network) }

    context "with an EVM network" do
      let(:network) { "eip155:84532" }

      it { is_expected.to eq(:evm) }
    end

    context "with a Solana network" do
      let(:network) { "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1" }

      it { is_expected.to eq(:svm) }
    end

    ["sui:mainnet", "base-sepolia", "eip155:", ""].each do |unsupported|
      context "with #{unsupported.inspect}" do
        let(:network) { unsupported }

        it "raises instead of defaulting to a family" do
          expect { family }.to raise_error(ArgumentError, /unsupported x402 network/)
        end
      end
    end
  end

  describe ".family_of_address" do
    subject(:family) { described_class.family_of_address(address) }

    %w[0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed 0x5AAEB6053F3E94C9B9A09F33669435E7EF1BEAED 0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed].each do |evm_address|
      context "with the EVM address #{evm_address}" do
        let(:address) { evm_address }

        it { is_expected.to eq(:evm) }
      end
    end

    context "with a Solana address" do
      let(:address) { solana_address }

      it { is_expected.to eq(:svm) }
    end

    {
      "truncated hex" => "0x5aaeb6053f3e94c9b9a09f33669435e7ef1bea",
      "a bare 40-hex address" => "5aaeb6053f3e94c9b9a09f33669435e7ef1beaed",
      "a base58 transaction signature" => X402::Base58.encode("\x01".b * 64),
      "an O→0 transcription" => "2wKupLR9q6wXYppw8Gr2NvWxKBUqm4PPJKkQf0xHDBg4",
      "a CAIP-10 account id" => "eip155:8453:0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed",
      "a 33-byte base58 string" => "z" * 44,
      "an empty string" => "",
      "nil" => nil
    }.each do |shape, malformed|
      context "with #{shape}" do
        let(:address) { malformed }

        it { is_expected.to be_nil }
      end
    end
  end

  describe ".checksum" do
    %w[
      0x52908400098527886E0F7030069857D2E4169EE7
      0x8617E340B3D01FA5F11F306F4090FD50E238070D
      0xde709f2102306220921060314715629080e2fb77
      0x27b1fdb04752bbc536007a920d24acb045561c26
      0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed
      0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359
      0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB
      0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb
    ].each do |vector|
      it "checksums #{vector.downcase}" do
        expect(described_class.checksum(vector.downcase)).to eq(vector)
      end
    end

    it "raises on something that is not an EVM address" do
      expect { described_class.checksum(solana_address) }.to raise_error(ArgumentError, /not an EVM address/)
    end
  end

  describe ".valid_address?" do
    subject(:valid) { described_class.valid_address?(address, family:) }

    context "with the EVM family" do
      let(:family) { :evm }

      {
        "all lowercase" => "0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed",
        "all uppercase" => "0x5AAEB6053F3E94C9B9A09F33669435E7EF1BEAED",
        "a correct checksum" => "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"
      }.each do |form, candidate|
        context "with #{form}" do
          let(:address) { candidate }

          it { is_expected.to be(true) }
        end
      end

      context "with one letter's case flipped" do
        let(:address) { "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAeD" }

        it { is_expected.to be(false) }
      end

      context "with a Solana address" do
        let(:address) { solana_address }

        it { is_expected.to be(false) }
      end
    end

    context "with the SVM family" do
      let(:family) { :svm }

      context "with a 32-byte key" do
        let(:address) { solana_address }

        it { is_expected.to be(true) }
      end

      context "with a 33-byte base58 string" do
        let(:address) { "z" * 44 }

        it { is_expected.to be(false) }
      end
    end

    context "with an unknown family" do
      let(:family) { :sui }
      let(:address) { solana_address }

      it "raises" do
        expect { valid }.to raise_error(ArgumentError, /unknown chain family/)
      end
    end
  end

  describe ".normalize_address" do
    subject(:normalized) { described_class.normalize_address(address, family:) }

    let(:family) { :evm }

    %w[0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed 0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed].each do |spelling|
      context "with #{spelling}" do
        let(:address) { spelling }

        it { is_expected.to eq("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed") }
      end
    end

    context "with a wrong checksum" do
      let(:address) { "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAeD" }

      it "comes back unchanged for the format check to report" do
        expect(normalized).to eq(address)
      end
    end

    context "with a Solana address" do
      let(:family) { :svm }
      let(:address) { solana_address }

      it "is kept verbatim" do
        expect(normalized).to eq(solana_address)
      end
    end
  end

  describe ".environment" do
    {
      "eip155:8453" => :mainnet,
      "eip155:84532" => :testnet,
      "solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp" => :mainnet,
      "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1" => :testnet
    }.each do |network, environment|
      it "places #{network} on #{environment}" do
        expect(described_class.environment(network)).to eq(environment)
      end
    end

    it "raises on a network Lago does not settle on" do
      expect { described_class.environment("eip155:1") }.to raise_error(ArgumentError, /unsupported x402 network/)
    end
  end
end
