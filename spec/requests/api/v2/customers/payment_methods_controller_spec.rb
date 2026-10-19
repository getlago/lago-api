# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::Customers::PaymentMethodsController do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:customer) { create(:customer, organization:) }
  let(:payment_method) { create(:payment_method, organization:, customer:, is_default: false) }
  let(:customer_path) { "/api/v2/customers/#{customer.external_id}" }

  describe "GET /api/v2/customers/:external_id/payment_methods" do
    subject { get_with_token(organization, "#{customer_path}/payment_methods", params) }

    let(:params) { {} }

    before do
      payment_method
      create(:payment_method, organization:, customer: create(:customer, organization:))
    end

    include_examples "requires API permission", "payment_method", "read"

    it "lists the payment methods of the customer only, with the v2 payload" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:payment_methods].sole).to include(
        lago_id: payment_method.id,
        lago_customer_id: customer.id,
        external_customer_id: customer.external_id,
        is_default: false,
        deleted_at: nil
      )
      expect(json[:meta]).to eq(next_cursor: nil, prev_cursor: nil)
    end

    it_behaves_like "a cursor paginated v2 endpoint", collection: :payment_methods, model: PaymentMethod do
      let(:paginated_path) { "#{customer_path}/payment_methods" }
      let(:create_paginated_record) { ->(created_at) { create(:payment_method, organization:, customer:, is_default: false, created_at:) } }
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
      let(:params) { {expands: %w[customer]} }

      it "refuses them, as a list never expands" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("expand_not_supported")
      end
    end

    context "with an unknown customer" do
      let(:customer_path) { "/api/v2/customers/unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("customer")
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

  describe "PUT /api/v2/customers/:external_id/payment_methods/:id/set_as_default" do
    subject { put_with_token(organization, "#{customer_path}/payment_methods/#{payment_method_id}/set_as_default") }

    let(:payment_method_id) { payment_method.id }

    include_examples "requires API permission", "payment_method", "write"

    it "makes it the default payment method and returns it" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:payment_method]).to include(lago_id: payment_method.id, is_default: true)
    end

    context "with a payment method of another customer" do
      let(:payment_method_id) { create(:payment_method, organization:, customer: create(:customer, organization:)).id }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("payment_method")
      end
    end
  end

  describe "DELETE /api/v2/customers/:external_id/payment_methods/:id" do
    subject { delete_with_token(organization, "#{customer_path}/payment_methods/#{payment_method.id}") }

    include_examples "requires API permission", "payment_method", "write"

    it "discards the payment method and returns it with its deletion time" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:payment_method][:lago_id]).to eq(payment_method.id)
      expect(json[:payment_method][:deleted_at]).to be_present
      expect(payment_method.reload).to be_discarded
    end
  end
end
