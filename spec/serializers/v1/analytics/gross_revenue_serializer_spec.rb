# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::Analytics::GrossRevenueSerializer do
  subject(:serializer) { described_class.new(gross_revenue, root_name: "gross_revenue") }

  let(:gross_revenue) do
    {
      "month" => "2024-06-01T00:00:00Z",
      "amount_cents" => 100,
      "currency" => "EUR",
      "invoices_count" => 1,
      "billing_entity_id" => "be-id-1"
    }
  end

  let(:result) { JSON.parse(serializer.to_json) }

  it "serializes the gross revenue" do
    expect(result["gross_revenue"]).to eq(
      {
        "month" => "2024-06-01T00:00:00Z",
        "amount_cents" => 100,
        "currency" => "EUR",
        "invoices_count" => 1,
        "billing_entity_id" => "be-id-1"
      }
    )
  end

  context "when amount_cents is a BigDecimal" do
    before { gross_revenue["amount_cents"] = BigDecimal("1000.0") }

    it "serializes it as an integer" do
      expect(result["gross_revenue"]["amount_cents"]).to be(1000)
    end
  end

  context "when amount_cents is a float" do
    before { gross_revenue["amount_cents"] = 1000.0 }

    it "serializes it as an integer" do
      expect(result["gross_revenue"]["amount_cents"]).to be(1000)
    end
  end

  context "when amount_cents is nil" do
    before { gross_revenue["amount_cents"] = nil }

    it "serializes it as nil" do
      expect(result["gross_revenue"]["amount_cents"]).to be_nil
    end
  end

  context "when invoices_count is a BigDecimal" do
    before { gross_revenue["invoices_count"] = BigDecimal("2.0") }

    it "serializes it as an integer" do
      expect(result["gross_revenue"]["invoices_count"]).to be(2)
    end
  end
end
