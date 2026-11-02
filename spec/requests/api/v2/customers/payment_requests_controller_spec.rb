# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::Customers::PaymentRequestsController do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:customer) { create(:customer, organization:) }
  let(:invoices) { create_list(:invoice, 2, organization:, customer:) }
  let(:payment_request) { create(:payment_request, organization:, customer:, invoices:) }
  let(:customer_path) { "/api/v2/customers/#{customer.external_id}" }

  describe "GET /api/v2/customers/:external_id/payment_requests" do
    subject { get_with_token(organization, "#{customer_path}/payment_requests", params) }

    let(:params) { {} }

    before do
      payment_request
      create(:payment_request, organization:, customer: create(:customer, organization:))
    end

    include_examples "requires API permission", "payment_request", "read"

    it "lists the payment requests of the customer only, with the v2 payload" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:payment_requests].sole).to include(
        lago_id: payment_request.id,
        lago_customer_id: customer.id,
        external_customer_id: customer.external_id,
        currency: "EUR",
        payment_status: "pending"
      )
      expect(json[:payment_requests].sole[:lago_invoice_ids]).to match_array(invoices.map(&:id))
      expect(json[:meta]).to eq(next_cursor: nil, prev_cursor: nil)
    end

    it_behaves_like "a cursor paginated v2 endpoint", collection: :payment_requests, model: PaymentRequest do
      let(:paginated_path) { "#{customer_path}/payment_requests" }
      let(:create_paginated_record) { ->(created_at) { create(:payment_request, organization:, customer:, created_at:) } }
    end

    it_behaves_like "a v2 list filtered on created_at", collection: :payment_requests do
      let(:filtered_path) { "#{customer_path}/payment_requests" }
      let(:create_filtered_record) { ->(created_at) { create(:payment_request, organization:, customer:, created_at:) } }
    end

    context "with offset pagination parameters" do
      let(:params) { {page: 2} }

      it "refuses them, as the list pages with cursors" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("invalid_pagination_parameter")
      end
    end

    context "with expands" do
      let(:params) { {expands: %w[invoices]} }

      it "refuses them, as a list never expands" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("expand_not_supported")
      end
    end

    context "with a deleted customer sharing the external id" do
      before do
        deleted_customer = create(:customer, organization:, external_id: customer.external_id, deleted_at: Time.current)
        create(:payment_request, organization:, customer: deleted_customer)
      end

      it "lists the payment requests of the current customer only" do
        subject

        expect(json[:payment_requests].map { it[:lago_id] }).to eq([payment_request.id])
      end
    end

    context "with an unknown customer" do
      let(:customer_path) { "/api/v2/customers/unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("customer")
      end
    end

    context "when the organization is not on the product catalog", product_catalog: false do
      let(:organization) { create(:organization) }

      it "returns a forbidden error" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end
  end
end
