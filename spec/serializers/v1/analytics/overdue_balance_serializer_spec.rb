# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::Analytics::OverdueBalanceSerializer do
  subject(:serializer) { described_class.new(overdue_balance, root_name: "overdue_balance") }

  let(:overdue_balance) do
    {
      "month" => "2024-06-01T00:00:00Z",
      "amount_cents" => 100,
      "currency" => "EUR",
      "lago_invoice_ids" => "[\"1\", \"2\", \"3\"]",
      "billing_entity_id" => "be-id-1"
    }
  end

  let(:result) { JSON.parse(serializer.to_json) }

  it "serializes the overdue balance" do
    expect(result["overdue_balance"]).to eq(
      {
        "month" => "2024-06-01T00:00:00Z",
        "amount_cents" => 100,
        "currency" => "EUR",
        "lago_invoice_ids" => ["1", "2", "3"],
        "billing_entity_id" => "be-id-1"
      }
    )
  end

  context "when amount_cents is a BigDecimal" do
    before { overdue_balance["amount_cents"] = BigDecimal("1000.0") }

    it "serializes it as an integer" do
      expect(result["overdue_balance"]["amount_cents"]).to be(1000)
    end
  end

  context "when amount_cents is a float" do
    before { overdue_balance["amount_cents"] = 1000.0 }

    it "serializes it as an integer" do
      expect(result["overdue_balance"]["amount_cents"]).to be(1000)
    end
  end

  context "when amount_cents is nil" do
    before { overdue_balance["amount_cents"] = nil }

    it "serializes it as nil" do
      expect(result["overdue_balance"]["amount_cents"]).to be_nil
    end
  end
end
