# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::Customers::CreditNotesController do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, external_id: "customer-1") }
  let(:other_customer) { create(:customer, organization:, external_id: "customer-2") }
  let(:invoice) { create(:invoice, organization:, customer:) }
  let(:credit_notes) { create_list(:credit_note, 3, invoice:, customer:) }
  let(:path) { "/api/v2/customers/#{customer.external_id}/credit_notes" }
  let(:params) { {} }

  before do
    organization.enable_feature_flag!(:product_catalog)
    credit_notes
  end

  describe "GET /api/v2/customers/:customer_external_id/credit_notes" do
    subject(:request) { get_with_token(organization, path, params) }

    include_examples "requires API permission", "credit_note", "read"

    it "returns the customer's credit notes as a v2 cursor page" do
      request

      sorted_credit_notes = credit_notes.sort_by { [it.created_at, it.id] }.reverse
      expect(response).to have_http_status(:ok)
      expect(json[:credit_notes].map { it[:lago_id] }).to eq(sorted_credit_notes.map(&:id))
      expect(json[:meta]).to eq(next_cursor: nil, prev_cursor: nil)
      expect(json[:credit_notes].first[:created_at]).to eq(sorted_credit_notes.first.created_at.iso8601(6))
    end

    it_behaves_like "a cursor paginated v2 endpoint", collection: :credit_notes, model: CreditNote do
      let(:paginated_path) { path }
      let(:create_paginated_record) do
        ->(created_at) { create(:credit_note, invoice:, customer:, created_at:) }
      end
    end

    context "with a reason filter" do
      let(:credit_notes) { [] }
      let(:matching_credit_note) { create(:credit_note, invoice:, customer:, reason: "duplicated_charge") }
      let(:nonmatching_credit_note) { create(:credit_note, invoice:, customer:, reason: "other") }
      let(:foreign_invoice) { create(:invoice, organization:, customer: other_customer) }
      let(:foreign_credit_note) { create(:credit_note, invoice: foreign_invoice, customer: other_customer) }
      let(:params) { {reason: "duplicated_charge"} }

      before do
        matching_credit_note
        nonmatching_credit_note
        foreign_credit_note
      end

      it "filters the results without leaking credit notes for another customer" do
        request

        expect(json[:credit_notes].map { it[:lago_id] }).to eq([matching_credit_note.id])
      end
    end

    context "with an amount bound that is not an integer" do
      let(:params) { {amount_from: "abc"} }

      it "returns a validation error on the bound" do
        request

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "validation_errors", details: [{code: "value_is_invalid", field: "amount_from", meta: {}}])
      end
    end

    context "when the customer does not belong to the organization" do
      let(:foreign_customer) { create(:customer, external_id: "foreign-customer") }
      let(:path) { "/api/v2/customers/#{foreign_customer.external_id}/credit_notes" }

      it "returns customer not found" do
        request

        expect(response).to be_v2_not_found_error("customer")
      end
    end

    context "when the customer does not exist" do
      let(:path) { "/api/v2/customers/missing/credit_notes" }

      it "returns customer not found" do
        request

        expect(response).to be_v2_not_found_error("customer")
      end
    end

    context "when the product catalog is disabled" do
      before { organization.disable_feature_flag!(:product_catalog) }

      it "returns a forbidden error" do
        request

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end

    context "with invalid cursor parameters" do
      let(:params) { {page: 2} }

      it "rejects offset pagination" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("invalid_pagination_parameter")
      end
    end
  end
end
