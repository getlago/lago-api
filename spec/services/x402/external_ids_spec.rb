# frozen_string_literal: true

require "rails_helper"

describe X402::ExternalIds do
  let(:checksummed) { "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed" }
  let(:solana_address) { "2wKupLR9q6wXYppw8Gr2NvWxKBUqm4PPJKkQfoxHDBg4" }

  describe ".customer" do
    it "is built from the checksummed address" do
      expect(described_class.customer(checksummed.downcase, family: :evm)).to eq("x402_#{checksummed}")
    end

    it "is the same for every spelling of one EVM address" do
      expect(described_class.customer(checksummed.upcase.sub("0X", "0x"), family: :evm)).to eq(described_class.customer(checksummed, family: :evm))
    end

    it "keeps a Solana address verbatim" do
      expect(described_class.customer(solana_address, family: :svm)).to eq("x402_#{solana_address}")
    end

    it "raises on an invalid address" do
      expect { described_class.customer("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAeD", family: :evm) }.to raise_error(ArgumentError, /invalid evm address/)
    end
  end

  describe ".subscription" do
    it "appends the plan code" do
      expect(described_class.subscription(checksummed.downcase, "agents", family: :evm)).to eq("x402_#{checksummed}_agents")
    end

    it "is the same for every spelling of one EVM address" do
      expect(described_class.subscription(checksummed.downcase, "agents", family: :evm)).to eq(described_class.subscription(checksummed, "agents", family: :evm))
    end

    it "raises on an invalid address" do
      expect { described_class.subscription("", "agents", family: :svm) }.to raise_error(ArgumentError, /invalid svm address/)
    end
  end
end
