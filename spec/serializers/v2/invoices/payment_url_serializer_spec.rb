# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::Invoices::PaymentUrlSerializer do
  subject(:serializer) { described_class.new(described_class::PaymentUrl.new(invoice:, url: "https://example.com"), root_name: "payment_url") }

  let(:customer) { create(:customer, payment_provider: "stripe") }
  let(:invoice) { create(:invoice, customer:, invoice_type: :contract) }

  it "serializes the payment details" do
    expect(JSON.parse(serializer.to_json)["payment_url"]).to eq(
      "lago_customer_id" => customer.id,
      "external_customer_id" => customer.external_id,
      "payment_provider" => "stripe",
      "lago_invoice_id" => invoice.id,
      "payment_url" => "https://example.com"
    )
  end
end
