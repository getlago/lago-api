# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::Analytics::InvoiceCollectionSerializer do
  subject(:serializer) { described_class.new(invoice_collection, root_name: "invoice_collection") }

  let(:invoice_collection) do
    {
      "month" => Time.current.beginning_of_month.iso8601,
      "payment_status" => "succeeded",
      "invoices_count" => 1,
      "currency" => "EUR",
      "amount_cents" => 100
    }
  end

  let(:result) { JSON.parse(serializer.to_json) }

  it "serializes the invoice collection" do
    expect(result["invoice_collection"]["month"]).to eq(Time.current.beginning_of_month.iso8601)
    expect(result["invoice_collection"]["payment_status"]).to eq("succeeded")
    expect(result["invoice_collection"]["invoices_count"]).to eq(1)
    expect(result["invoice_collection"]["currency"]).to eq("EUR")
    expect(result["invoice_collection"]["amount_cents"]).to eq(100)
  end

  context "when amount_cents is a BigDecimal" do
    before { invoice_collection["amount_cents"] = BigDecimal("1000.0") }

    it "serializes it as an integer" do
      expect(result["invoice_collection"]["amount_cents"]).to be(1000)
    end
  end

  context "when amount_cents is a float" do
    before { invoice_collection["amount_cents"] = 1000.0 }

    it "serializes it as an integer" do
      expect(result["invoice_collection"]["amount_cents"]).to be(1000)
    end
  end

  context "when amount_cents is nil" do
    before { invoice_collection["amount_cents"] = nil }

    it "serializes it as nil" do
      expect(result["invoice_collection"]["amount_cents"]).to be_nil
    end
  end
end
