# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::Invoices::PaymentUrlsController do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:legacy_invoice) { create(:invoice, organization:, customer:) }

  describe "POST /api/v2/invoices/:id/payment_url" do
    subject { post_with_token(organization, "/api/v2/invoices/#{invoice_id}/payment_url") }

    let(:customer) { create(:customer, organization:, payment_provider: "stripe", payment_provider_code: stripe_provider.code) }
    let(:stripe_provider) { create(:stripe_provider, organization:, code: "stripe_1") }
    let(:invoice) { create(:invoice, organization:, customer:, invoice_type: :contract, status:) }
    let(:invoice_id) { invoice.id }
    let(:status) { :finalized }

    before do
      create(:stripe_customer, customer:, payment_provider: stripe_provider)
      allow(::Stripe::Checkout::Session).to receive(:create).and_return({"url" => "https://example.com"})
    end

    include_examples "requires API permission", "invoice", "write"

    it "returns the generated payment url" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:payment_url]).to eq(
        lago_customer_id: customer.id,
        external_customer_id: customer.external_id,
        payment_provider: "stripe",
        lago_invoice_id: invoice.id,
        payment_url: "https://example.com"
      )
    end

    context "when the invoice is a draft" do
      let(:status) { :draft }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json).to eq(code: "validation_errors", details: [{code: "invalid_invoice_status_or_payment_status", field: "base", meta: {}}])
      end
    end

    context "when the invoice is a legacy one" do
      let(:invoice_id) { legacy_invoice.id }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("invoice")
        expect(::Stripe::Checkout::Session).not_to have_received(:create)
      end
    end
  end
end
