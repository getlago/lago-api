# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::Customers::PaymentRequestsController do
  describe "GET /api/v2/customers/:external_id/payment_requests" do
    subject { get_with_token(organization, "/api/v2/customers/#{external_id}/payment_requests", params) }

    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }
    let(:external_id) { customer.external_id }
    let(:params) { {} }
    let(:contract_invoice) { create(:invoice, organization:, customer:, invoice_type: :contract) }
    let(:legacy_invoice) { create(:invoice, organization:, customer:) }
    let(:payment_request) { create(:payment_request, customer:, invoices: [contract_invoice, legacy_invoice]) }
    let(:other_payment_request) { create(:payment_request, customer:, invoices: [create(:invoice, organization:, customer:)]) }

    before do
      payment_request
      create(:payment_request, customer: create(:customer, organization:))
    end

    include_examples "requires API permission", "payment_request", "read"

    it "lists the payment requests of the customer only" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:payment_requests].map { it[:lago_id] }).to eq([payment_request.id])
      expect(json[:meta]).to include(current_page: 1, total_count: 1)
    end

    it "renders catalog invoices with the v2 shape and legacy invoices with the v1 shape" do
      subject

      invoices = json[:payment_requests].sole[:invoices].index_by { it[:lago_id] }

      expect(invoices.keys).to contain_exactly(contract_invoice.id, legacy_invoice.id)
      expect(invoices[contract_invoice.id]).to include(invoice_type: "contract")
      expect(invoices[contract_invoice.id]).not_to have_key(:sequential_id)
      expect(invoices[legacy_invoice.id]).to include(sequential_id: legacy_invoice.sequential_id)
    end

    context "with several payment requests" do
      before { other_payment_request }

      it "classifies the invoices of the whole page with one query" do
        contract_fee_queries = []
        callback = ->(*, payload) { contract_fee_queries << payload[:sql] if payload[:sql].include?('"fees"."contract_id" IS NOT NULL') }

        ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { subject }

        expect(json[:payment_requests].size).to eq(2)
        expect(contract_fee_queries.size).to eq(1)
      end
    end

    context "when a payment request holds more catalog and legacy invoices" do
      let(:request_query_count) do
        lambda do
          queries = 0
          callback = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" }
          ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
            get_with_token(organization, "/api/v2/customers/#{external_id}/payment_requests", params)
          end
          queries
        end
      end

      it "does not run more queries" do
        request_query_count.call
        baseline = request_query_count.call

        invoices = create_list(:invoice, 3, organization:, customer:, invoice_type: :contract) + create_list(:invoice, 3, organization:, customer:)
        invoices.each { create(:payment_request_applied_invoice, payment_request:, invoice: it, organization:) }

        expect(request_query_count.call).to be <= baseline
      end
    end

    context "when the page holds more payment requests" do
      let(:request_query_count) do
        lambda do
          queries = 0
          callback = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" }
          ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
            get_with_token(organization, "/api/v2/customers/#{external_id}/payment_requests", params)
          end
          queries
        end
      end

      it "does not run more queries" do
        request_query_count.call
        baseline = request_query_count.call

        create_list(:invoice, 3, organization:, customer:, invoice_type: :contract).each do |invoice|
          create(:payment_request, customer:, invoices: [invoice])
        end

        expect(request_query_count.call).to be <= baseline
        expect(json[:payment_requests].size).to eq(4)
      end
    end

    context "when the organization is not on the product catalog", product_catalog: false do
      it "returns a forbidden error" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end

    context "with unknown customer" do
      let(:external_id) { SecureRandom.uuid }

      it "returns a not found error" do
        subject

        expect(response).to have_http_status(:not_found)
        expect(json[:code]).to eq("customer_not_found")
      end
    end
  end
end
