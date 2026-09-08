# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::Analytics::MrrSerializer do
  subject(:serializer) { described_class.new(mrr, root_name: "mrr") }

  let(:mrr) do
    {
      "month" => Time.current.beginning_of_month.iso8601,
      "amount_cents" => 100,
      "currency" => "EUR"
    }
  end

  let(:result) { JSON.parse(serializer.to_json) }

  it "serializes the gross revenue" do
    expect(result["mrr"]["month"]).to eq(Time.current.beginning_of_month.iso8601)
    expect(result["mrr"]["amount_cents"]).to eq(100)
    expect(result["mrr"]["currency"]).to eq("EUR")
  end

  context "when amount_cents is a BigDecimal" do
    before { mrr["amount_cents"] = BigDecimal("1000.0") }

    it "serializes it as an integer" do
      expect(result["mrr"]["amount_cents"]).to be(1000)
    end
  end

  context "when amount_cents is a float" do
    before { mrr["amount_cents"] = 1000.0 }

    it "serializes it as an integer" do
      expect(result["mrr"]["amount_cents"]).to be(1000)
    end
  end

  context "when amount_cents is nil" do
    before { mrr["amount_cents"] = nil }

    it "serializes it as nil" do
      expect(result["mrr"]["amount_cents"]).to be_nil
    end
  end
end
