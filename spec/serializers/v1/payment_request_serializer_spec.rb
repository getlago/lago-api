# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::PaymentRequestSerializer do
  subject(:serializer) do
    described_class.new(payment_request, root_name: "payment_request")
  end

  let(:payable_group) { create(:payable_group) }
  let(:payment_request) { create(:payment_request, payment_requestable: payable_group) }

  it "serializes the object" do
    invoice = create(:invoice, payable_group:)
    result = JSON.parse(serializer.to_json)

    aggregate_failures do
      expect(result["payment_request"]).to include(
        "lago_id" => payment_request.id,
        "email" => payment_request.email,
        "amount_cents" => payment_request.amount_cents,
        "amount_currency" => payment_request.amount_currency,
        "created_at" => payment_request.created_at.iso8601,
        "lago_invoice_ids" => [invoice.id]
      )
    end
  end
end
