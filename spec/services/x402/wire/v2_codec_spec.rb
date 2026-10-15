# frozen_string_literal: true

require "rails_helper"

describe X402::Wire::V2Codec do
  let(:entry) do
    {
      scheme: "exact",
      network: "eip155:84532",
      asset: "usdc",
      asset_address: "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
      extra: {"name" => "USDC", "version" => "2"},
      pay_to: "0x94bA479439C2f1bA5f5DaCBD06Ea0c129604B4a5",
      amount_atomic: "1050000",
      max_timeout_seconds: 60
    }
  end

  describe ".decode" do
    subject(:decoded) { described_class.decode(header) }

    let(:header) { Base64.strict_encode64({"x402Version" => 2}.to_json) }

    it { is_expected.to eq({"x402Version" => 2}) }

    context "with a header that is not base64" do
      let(:header) { "not base64!" }

      it { is_expected.to be_nil }
    end

    context "with a header that is not JSON" do
      let(:header) { Base64.strict_encode64("{") }

      it { is_expected.to be_nil }
    end

    context "with a JSON array" do
      let(:header) { Base64.strict_encode64("[]") }

      it { is_expected.to be_nil }
    end

    context "with bytes that are not UTF-8" do
      let(:header) { Base64.strict_encode64("\xFF\xFE".b) }

      it { is_expected.to be_nil }
    end

    context "without a header" do
      let(:header) { nil }

      it { is_expected.to be_nil }
    end
  end

  describe ".encode" do
    it "round-trips through decode" do
      expect(described_class.decode(described_class.encode({"success" => true}))).to eq({"success" => true})
    end
  end

  describe ".requirement" do
    it "renders the wire shape" do
      expect(described_class.requirement(entry)).to eq(
        "scheme" => "exact",
        "network" => "eip155:84532",
        "amount" => "1050000",
        "asset" => "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
        "payTo" => "0x94bA479439C2f1bA5f5DaCBD06Ea0c129604B4a5",
        "maxTimeoutSeconds" => 60,
        "extra" => {"name" => "USDC", "version" => "2"}
      )
    end
  end

  describe ".payment_required" do
    subject(:payment_required) { described_class.payment_required(requirements: [entry], resource:, error:) }

    let(:resource) { {"url" => "https://api.example.com/x402/invoice_payments/abc", "description" => "Invoice 1", "mimeType" => "application/json"} }
    let(:error) { nil }

    it "renders a v2 challenge without extensions" do
      expect(payment_required).to eq(
        "x402Version" => 2,
        "resource" => resource,
        "accepts" => [described_class.requirement(entry)]
      )
    end

    context "with a refused payment" do
      let(:error) { "amount_mismatch" }

      it "names the refusal" do
        expect(payment_required["error"]).to eq("amount_mismatch")
      end
    end
  end

  describe ".invoice_resource" do
    let(:invoice) { create(:invoice, x402_payment_token: "ab" * 32) }

    it "points at the invoice's payment link" do
      expect(described_class.invoice_resource(invoice)).to eq(
        "url" => invoice.x402_payment_url,
        "description" => "Invoice #{invoice.number}",
        "mimeType" => "application/json"
      )
    end
  end

  describe ".settlement_response" do
    let(:settlement) { create(:x402_settlement, :invoice_payment) }

    it "renders the receipt from the row" do
      expect(described_class.settlement_response(settlement)).to eq(
        "success" => true,
        "transaction" => settlement.transaction_hash,
        "network" => "eip155:84532",
        "payer" => settlement.payer_address
      )
    end
  end
end
