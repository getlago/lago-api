# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::InvoicesController do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:customer) { create(:customer, organization:) }

  describe "POST /api/v2/invoices/:id/void" do
    subject { post_with_token(organization, "/api/v2/invoices/#{invoice_id}/void", params) }

    let(:invoice) { create(:invoice, status:, payment_status: :pending, customer:, organization:) }
    let(:invoice_id) { invoice.id }
    let(:status) { :finalized }
    let(:params) { {} }
    let(:contract_rate_card) do
      create(:contract_rate_card, organization:, contract: create(:contract, organization:, customer:))
    end

    before do
      create(:fee, invoice:, subscription: nil, fee_type: :product,
        invoiceable: contract_rate_card.rate_card.product, contract: contract_rate_card.contract, contract_rate_card:)
    end

    include_examples "requires API permission", "invoice", "write"

    it "voids the contract invoice and returns it" do
      subject

      expect(response).to have_http_status(:success)
      expect(invoice.reload).to be_voided
      expect(json[:invoice]).to include(lago_id: invoice.id, status: "voided")
      expect(json[:invoice][:fees].pluck(:lago_id)).to eq(invoice.fees.ids)
    end

    context "when the invoice does not exist" do
      let(:invoice_id) { SecureRandom.uuid }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("invoice")
      end
    end

    context "when the invoice is a draft" do
      let(:status) { :draft }

      it "returns a not voidable error" do
        subject

        expect(response).to have_http_status(:method_not_allowed)
        expect(json[:code]).to eq("not_voidable")
        expect(invoice.reload).to be_draft
      end
    end

    context "when the organization is not on the product catalog", product_catalog: false do
      let(:organization) { create(:organization) }

      it "returns a forbidden error" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
        expect(invoice.reload).to be_finalized
      end
    end
  end
end
