# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::Analytics::GrossRevenueSerializer do
  subject(:serializer) { described_class.new(gross_revenue, root_name: "gross_revenue") }

  let(:gross_revenue) do
    {
      "month" => Time.current.beginning_of_month.iso8601,
      "amount_cents" => 100,
      "currency" => "EUR"
    }
  end

  let(:result) { JSON.parse(serializer.to_json) }

  it "serializes the gross revenue" do
    aggregate_failures do
      expect(result["gross_revenue"]["month"]).to eq(Time.current.beginning_of_month.iso8601)
      expect(result["gross_revenue"]["amount_cents"]).to eq(100)
      expect(result["gross_revenue"]["currency"]).to eq("EUR")
    end
  end
end
