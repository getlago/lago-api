# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::PaymentSerializer do
  subject(:result) { JSON.parse(described_class.new(payment, root_name: "payment").to_json)["payment"] }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, organization:, customer:) }
  let(:payment) { create(:payment, payable: invoice, provider_payment_data: {"type" => "redirect"}) }

  it "serializes the payment" do
    expect(result).to eq(
      "lago_id" => payment.id,
      "lago_customer_id" => customer.id,
      "external_customer_id" => customer.external_id,
      "lago_payable_id" => invoice.id,
      "payable_type" => "Invoice",
      "lago_invoice_ids" => [invoice.id],
      "amount_cents" => 200,
      "currency" => "EUR",
      "status" => "pending",
      "payment_status" => "pending",
      "payment_type" => "provider",
      "reference" => nil,
      "payment_provider_code" => payment.payment_provider.code,
      "payment_provider_type" => "stripe",
      "provider_payment_id" => payment.provider_payment_id,
      "provider_customer_id" => payment.payment_provider_customer.provider_customer_id,
      "next_action" => {"type" => "redirect"},
      "created_at" => payment.created_at.iso8601,
      "updated_at" => payment.updated_at.iso8601
    )
  end

  context "when the payable is a payment request" do
    let(:other_invoice) { create(:invoice, organization:, customer:) }
    let(:payment_request) { create(:payment_request, organization:, customer:, invoices: [invoice, other_invoice]) }
    let(:payment) { create(:payment, payable: payment_request) }

    it "lists the invoices the request covers" do
      expect(result["lago_invoice_ids"]).to match_array([invoice.id, other_invoice.id])
    end
  end

  context "without a payment provider" do
    let(:payment) { create(:payment, payable: invoice, payment_provider: nil, payment_provider_customer: nil) }

    it "renders no provider" do
      expect(result).to include(
        "payment_provider_code" => nil,
        "payment_provider_type" => nil,
        "provider_customer_id" => nil
      )
    end
  end
end
