# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::FeesController do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, organization:, customer:) }
  let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:) }
  let(:rate_card_rate) { create(:rate_card_rate, organization:, rate_card: contract_rate_card.rate_card) }
  let(:invoice) { create(:invoice, organization:, customer:) }

  let(:fee_attributes) do
    {
      invoice:,
      subscription: nil,
      fee_type: :product,
      invoiceable: contract_rate_card.rate_card.product,
      contract:,
      contract_rate_card:,
      rate_card_rate:
    }
  end
  let(:uninvoiced_fee_attributes) do
    fee_attributes.merge(invoice: nil, organization:, billing_entity: customer.billing_entity)
  end
  let(:fee) { create(:fee, fee_attributes) }
  let(:legacy_fee) { create(:fee, invoice:) }
  let(:fee_id) { fee.id }

  describe "GET /api/v2/fees" do
    subject { get_with_token(organization, "/api/v2/fees", params) }

    let(:params) { {} }

    before do
      fee
      legacy_fee
    end

    include_examples "requires API permission", "fee", "read"

    it "lists the product fees only" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:fees].sole).to include(lago_id: fee.id, external_contract_id: contract.external_id, billing_timing: "arrears")
      expect(json[:meta]).to eq(next_cursor: nil, prev_cursor: nil)
    end

    it_behaves_like "a cursor paginated v2 endpoint", collection: :fees, model: Fee do
      let(:paginated_path) { "/api/v2/fees" }
      let(:create_paginated_record) { ->(created_at) { create(:fee, fee_attributes.merge(created_at:)) } }
    end

    context "with catalog code filters" do
      let(:params) { {product_code: fee.invoiceable.code, rate_card_code: contract_rate_card.rate_card.code} }
      let(:other_contract_rate_card) { create(:contract_rate_card, organization:, contract:) }

      before do
        create(
          :fee,
          fee_attributes.merge(
            invoiceable: other_contract_rate_card.rate_card.product,
            contract_rate_card: other_contract_rate_card,
            rate_card_rate: create(:rate_card_rate, organization:, rate_card: other_contract_rate_card.rate_card)
          )
        )
      end

      it "passes them to the query" do
        subject

        expect(json[:fees].map { it[:lago_id] }).to eq([fee.id])
      end
    end

    context "with filters" do
      let(:params) { {payment_status: "succeeded", external_customer_id: customer.external_id} }
      let(:succeeded_fee) { create(:fee, :succeeded, uninvoiced_fee_attributes) }
      let(:other_contract_rate_card) { create(:contract_rate_card, organization:) }

      before do
        succeeded_fee
        create(
          :fee,
          :succeeded,
          fee_attributes.merge(
            invoice: create(:invoice, organization:, customer: other_contract_rate_card.contract.customer),
            contract: other_contract_rate_card.contract,
            contract_rate_card: other_contract_rate_card
          )
        )
      end

      it "passes them to the query" do
        subject

        expect(json[:fees].map { it[:lago_id] }).to eq([succeeded_fee.id])
      end
    end

    context "with lago_invoice_id" do
      let(:params) { {lago_invoice_id: invoice.id} }

      before { create(:fee, uninvoiced_fee_attributes) }

      it "lists the fees of that invoice" do
        subject

        expect(json[:fees].map { it[:lago_id] }).to eq([fee.id])
      end
    end

    context "with an unknown payment status" do
      let(:params) { {payment_status: "paid"} }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json[:details]).to eq([{code: "value_is_invalid", field: "payment_status", meta: {}}])
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

  describe "GET /api/v2/fees/:id" do
    subject { get_with_token(organization, "/api/v2/fees/#{fee_id}") }

    include_examples "requires API permission", "fee", "read"

    it "returns the fee" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:fee]).to include(lago_id: fee.id, lago_invoice_id: invoice.id, billing_timing: "arrears")
    end

    context "with timestamps between two seconds" do
      let(:fee) do
        create(
          :fee,
          fee_attributes.merge(
            created_at: Time.zone.parse("2026-10-01T08:30:00.123456Z"),
            properties: {"from_datetime" => "2026-10-01T00:00:00.000Z", "to_datetime" => "2026-10-31T23:59:59.999Z"}
          )
        )
      end

      it "returns them to the microsecond, the billed period as its properties store it" do
        subject

        expect(json[:fee]).to include(
          from_datetime: "2026-10-01T00:00:00.000000Z",
          to_datetime: "2026-10-31T23:59:59.999000Z",
          created_at: "2026-10-01T08:30:00.123456Z"
        )
      end
    end

    context "when the fee is a legacy one" do
      let(:fee_id) { legacy_fee.id }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("fee")
      end
    end

    context "when the fee belongs to another organization" do
      let(:fee_id) { create(:fee, fee_attributes.merge(invoice: create(:invoice), contract: nil, contract_rate_card: nil)).id }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("fee")
      end
    end
  end

  describe "PUT /api/v2/fees/:id" do
    subject { put_with_token(organization, "/api/v2/fees/#{fee_id}", fee: {payment_status:}) }

    let(:fee) { create(:fee, uninvoiced_fee_attributes) }
    let(:payment_status) { "succeeded" }

    include_examples "requires API permission", "fee", "write"

    it "updates the payment status and returns the fee" do
      freeze_time do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:fee]).to include(lago_id: fee.id, payment_status: "succeeded", succeeded_at: Time.current.iso8601(6), billing_timing: "arrears")
        expect(fee.reload).to be_payment_succeeded
      end
    end

    context "when the fee is a legacy one" do
      let(:fee_id) { legacy_fee.id }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("fee")
        expect(legacy_fee.reload).to be_payment_pending
      end
    end

    context "when the fee is invoiced" do
      let(:fee) { create(:fee, fee_attributes) }

      it "returns a not allowed error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "invoiced_fee", details: [])
        expect(fee.reload).to be_payment_pending
      end
    end

    context "with an unknown payment status" do
      let(:payment_status) { "paid" }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json[:details]).to eq([{code: "value_is_invalid", field: "payment_status", meta: {}}])
      end
    end

    context "with a payment status that is not a string" do
      let(:payment_status) { 1 }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json).to eq(code: "validation_errors", details: [{code: "value_is_invalid", field: "payment_status", meta: {}}])
        expect(fee.reload).to be_payment_pending
      end
    end

    context "when the fee wrapper is missing" do
      subject { put_with_token(organization, "/api/v2/fees/#{fee_id}", {payment_status: "succeeded"}) }

      it "returns the v2 missing parameter error" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json).to eq(
          code: "missing_parameter",
          details: [{code: "missing", field: "fee", meta: {}}]
        )
      end
    end
  end

  describe "DELETE /api/v2/fees/:id" do
    subject { delete_with_token(organization, "/api/v2/fees/#{fee_id}") }

    let(:fee) { create(:fee, uninvoiced_fee_attributes) }

    include_examples "requires API permission", "fee", "write"

    it "discards the fee and returns it" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:fee]).to include(lago_id: fee.id, billing_timing: "arrears")
      expect(Fee.with_discarded.find(fee.id)).to be_discarded
    end

    context "when the fee is a legacy one" do
      let(:fee_id) { legacy_fee.id }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("fee")
        expect(legacy_fee.reload).to be_kept
      end
    end

    context "when the fee is invoiced" do
      let(:fee) { create(:fee, fee_attributes) }

      it "returns a not allowed error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "invoiced_fee", details: [])
        expect(fee.reload).to be_kept
      end
    end
  end

  describe "expansions" do
    subject(:request) { get_with_token(organization, "/api/v2/fees/#{fee_id}", {expands: names}) }

    let(:names) { %w[applied_taxes product product_filter rate_card rate contract customer] }
    let(:tax) { create(:tax, organization:) }

    before { create(:fee_applied_tax, fee:, tax:) }

    it "embeds each requested record after the fee" do
      request

      expect(response).to have_http_status(:ok)
      expect(json[:fee].keys.last(7)).to eq(names.map(&:to_sym))
      expect(json[:fee][:applied_taxes].map { it[:lago_tax_id] }).to eq([tax.id])
      expect(json[:fee][:applied_taxes].sole.values_at(:created_at, :updated_at)).to all(match(/\.\d{6}Z\z/))
      expect(json[:fee][:product][:lago_id]).to eq(fee.invoiceable_id)
      expect(json[:fee][:rate_card][:lago_id]).to eq(contract_rate_card.rate_card_id)
      expect(json[:fee][:rate][:lago_id]).to eq(rate_card_rate.id)
      expect(json[:fee][:contract][:lago_id]).to eq(contract.id)
      expect(json[:fee][:customer][:lago_id]).to eq(customer.id)
    end

    context "without expands" do
      let(:names) { [] }

      it "returns the flat fee" do
        request

        expect(response).to have_http_status(:ok)
        expect(json[:fee]).not_to include(:applied_taxes, :product, :customer)
      end
    end

    context "with a name the fee does not declare" do
      let(:names) { %w[applied_taxes subscription] }

      it "returns an invalid_expand error listing the fee expansions" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("invalid_expand")
        expect(json[:details]).to eq([
          {
            code: "invalid_expand",
            field: "expands",
            meta: {
              invalid_values: %w[subscription],
              allowed_values: %w[applied_taxes product product_filter rate_card rate contract customer]
            }
          }
        ])
      end
    end

    context "when listing fees" do
      subject(:request) { get_with_token(organization, "/api/v2/fees", {expands: %w[applied_taxes], limit: 0}) }

      it "refuses the expansion before reading the pagination" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("expand_not_supported")
        expect(json[:details]).to eq([{code: "action_not_expandable", field: "expands", meta: {invalid_values: %w[applied_taxes]}}])
      end
    end

    context "when deleting the fee" do
      subject(:request) { delete_with_token(organization, "/api/v2/fees/#{fee_id}?expands[]=applied_taxes") }

      let(:fee) { create(:fee, uninvoiced_fee_attributes) }

      it "refuses the expansion before deleting the fee" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("expand_not_supported")
        expect(fee.reload).to be_kept
      end
    end

    context "when the fee does not exist" do
      subject(:request) { get_with_token(organization, "/api/v2/fees/#{SecureRandom.uuid}", {expands: %w[bogus]}) }

      it "validates the expansion before looking up the fee" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("invalid_expand")
      end
    end
  end
end
