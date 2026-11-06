# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::PaymentRequestSerializer do
  subject(:result) { JSON.parse(described_class.new(payment_request, root_name: "payment_request").to_json)["payment_request"] }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, organization:, customer:) }
  let(:payment_request) { create(:payment_request, organization:, customer:, email: "billing@example.com", invoices: [invoice]) }

  it "serializes the payment request" do
    expect(result).to eq(
      "lago_id" => payment_request.id,
      "lago_customer_id" => customer.id,
      "external_customer_id" => customer.external_id,
      "email" => "billing@example.com",
      "amount_cents" => 200,
      "currency" => "EUR",
      "payment_status" => "pending",
      "lago_invoice_ids" => [invoice.id],
      "created_at" => payment_request.created_at.iso8601,
      "updated_at" => payment_request.updated_at.iso8601
    )
  end
end
