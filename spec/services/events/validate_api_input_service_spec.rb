# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::ValidateApiInputService do
  subject(:result) { described_class.call(params:, batch:) }

  let(:params) { {transaction_id: "transaction", code: "requests", external_contract_id: "contract", properties: {values: [1, nil]}} }
  let(:batch) { false }

  it "accepts arbitrary JSON property values" do
    expect(result).to be_success
  end

  context "when a scalar field is not a string" do
    let(:params) { super().merge(code: 123) }

    it "returns a validation failure before casting" do
      expect(result.error.messages).to eq(code: ["value_is_invalid"])
    end
  end

  context "with a finite amount" do
    let(:params) { super().merge(precise_total_amount_cents: "123.456") }

    it "accepts the decimal without converting it to a float" do
      expect(result).to be_success
    end
  end

  context "with an infinite amount" do
    let(:params) { super().merge(precise_total_amount_cents: "Infinity") }

    it "refuses it" do
      expect(result.error.messages).to eq(precise_total_amount_cents: ["value_is_invalid"])
    end
  end

  context "with an invalid root" do
    let(:params) { "invalid" }

    it "returns a base error" do
      expect(result.error.messages).to eq(base: ["value_is_invalid"])
    end
  end

  context "with a batch" do
    let(:batch) { true }
    let(:params) { [{transaction_id: "first", code: "requests"}, nil] }

    it "keeps the original index of the invalid entry" do
      expect(result.error.messages).to eq("events[1]": ["value_is_invalid"])
    end
  end
end
