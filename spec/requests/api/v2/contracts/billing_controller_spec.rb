# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::Contracts::BillingController do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:customer) { create(:customer, organization:, timezone: "UTC", currency: "EUR") }
  let(:contract) { create(:contract, organization:, customer:, external_id: "contract.1", started_at: Time.utc(2026, 1, 1)) }
  let(:product) { create(:product, :fixed, organization:) }
  let(:rate_card) { create(:rate_card, organization:, product:, currency: "EUR", billing_timing: "arrears", proration: false) }
  let(:rate) { create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 1)) }
  let(:card) { attach_card(contract) }
  let(:billing_scope) { "cycle" }
  let(:foreign_contract) { create(:contract) }

  def attach_card(contract)
    create(:contract_rate_card, organization:, contract:, rate_card:, billing_scope:, units: 3,
      effective_date: Date.new(2026, 1, 1), billing_anchor_date: Date.new(2026, 1, 1), next_billing_at: Time.utc(2026, 2, 1))
  end

  before do
    rate
    card
  end

  describe "GET /api/v2/contracts/:external_id/operations" do
    subject(:preview) { get_with_token(organization, "/api/v2/contracts/#{contract.external_id}/operations", params) }

    let(:params) { {start_on: "2026-01-20", end_on: "2026-02-01"} }
    let(:override) { create(:rate_override, organization:, rate_properties: {"amount" => "20"}) }
    let(:second_rate) { create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 20)) }

    before do
      second_rate
      create(:rate_phase, :contract_level, organization:, contract_rate_card: card, rate_override: override, code: "intro")
    end

    include_examples "requires API permission", "contract", "read"

    it "returns complete cycle obligations, including segments before the window, without advancing billing" do
      expect { preview }.not_to change(BillingOperation, :count)

      expect(response).to have_http_status(:ok)
      expect(json[:billing_obligations].pluck(:cycle_index)).to eq([1, 2])
      expect(json[:billing_obligations].first).to eq(
        external_contract_id: contract.external_id, external_customer_id: customer.external_id,
        lago_applied_rate_card_id: card.id, applied_rate_card_code: rate_card.code, cycle_index: 1,
        cycle_started_at: "2026-01-01T00:00:00.000000Z", billing_at: "2026-02-01T00:00:00.000000Z",
        billing_scope: "cycle", rate_phase_code: "intro",
        segments: [
          {period_from: "2026-01-01T00:00:00.000000Z", period_to: "2026-01-19T23:59:59.999999Z",
           lago_rate_id: rate.id, rate_code: rate.code, lago_rate_override_id: override.id, properties: {amount: "20"}, proration_ratio: 1},
          {period_from: "2026-01-20T00:00:00.000000Z", period_to: "2026-01-31T23:59:59.999999Z",
           lago_rate_id: second_rate.id, rate_code: second_rate.code, lago_rate_override_id: override.id, properties: {amount: "20"}, proration_ratio: 1}
        ]
      )
      expect(json[:next_billing_at]).to eq("2026-03-01T00:00:00.000000Z")
      expect(card.reload.next_billing_at).to eq(Time.utc(2026, 2, 1))
    end

    context "with segment billing scope" do
      let(:billing_scope) { "segment" }

      let(:params) { {start_on: "2026-01-19", end_on: "2026-01-31"} }

      it "returns separate obligations with their own billing date for each segment of the same cycle" do
        preview
        expect(json[:billing_obligations].pluck(:cycle_index, :billing_scope, :billing_at)).to eq([
          [1, "segment", "2026-01-20T00:00:00.000000Z"], [1, "segment", "2026-02-01T00:00:00.000000Z"]
        ])
        expect(json[:billing_obligations].map { it[:segments].sole[:lago_rate_id] }).to eq([rate.id, second_rate.id])
      end
    end

    it "accepts a collection of external IDs" do
      get_with_token(organization, "/api/v2/contracts/operations", params.merge(external_ids: [contract.external_id]))
      expect(response).to have_http_status(:ok)
      expect(json[:billing_obligations].pluck(:external_contract_id).uniq).to eq([contract.external_id])
    end

    context "with an external ID of operations" do
      let(:contract) { create(:contract, organization:, customer:, external_id: "operations", started_at: Time.utc(2026, 1, 1)) }

      it "preserves the existing contract show route without the ID list" do
        get_with_token(organization, "/api/v2/contracts/operations")
        expect(json[:contract][:lago_id]).to eq(contract.id)
      end
    end

    context "with an invalid window" do
      let(:params) { {start_on: ["not-a-date"], end_on: "2026-13-01"} }

      it "returns field errors for both dates" do
        preview
        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:details]).to eq(%w[start_on end_on].map { {field: it, code: "invalid_date", meta: {}} })
      end
    end

    context "when the window ends before it starts" do
      let(:params) { {start_on: "2026-02-01", end_on: "2026-01-31"} }

      it "rejects the end date" do
        preview
        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:details]).to eq([{field: "end_on", code: "value_is_invalid", meta: {}}])
      end
    end

    context "when the customer is ahead of UTC" do
      let(:customer) { create(:customer, organization:, timezone: "Asia/Tokyo") }
      let(:params) { {start_on: "2026-01-31", end_on: "2026-01-31"} }

      it "previews the customer's January 31 and reports the February close in UTC" do
        preview
        expect(response).to have_http_status(:ok)
        expect(json[:billing_obligations].sole[:segments].last[:period_to]).to eq("2026-01-31T14:59:59.999999Z")
        expect(json[:next_billing_at]).to eq("2026-01-31T15:00:00.000000Z")
      end
    end
  end

  describe "POST /api/v2/contracts/:external_id/bill", v2_timestamps: false do
    subject(:bill) { post_with_token(organization, "/api/v2/contracts/#{contract.external_id}/bill", params) }

    let(:params) { {end_on: "2026-03-01"} }

    before { stub_pdf_generation }

    include_examples "requires API permission", "contract", "write"

    it "bills all due cycles once and leaves historical previews unchanged" do
      preview_path = "/api/v2/contracts/#{contract.external_id}/operations"
      get_with_token(organization, preview_path, params)
      original = json

      bill
      expect(response).to have_http_status(:ok)
      expect(json[:invoices].pluck(:total_amount_cents)).to eq([3000, 3000]) # 3 units at EUR 10 each, per month
      expect(json[:invoices].first[:fees].sole[:item]).to include(type: "product", lago_item_id: product.id, code: product.code)
      expect(json[:invoices].first[:customer][:external_id]).to eq(customer.external_id)
      expect(card.reload.next_billing_at).to eq(Time.utc(2026, 4, 1))

      post_with_token(organization, "/api/v2/contracts/#{contract.external_id}/bill", params)
      expect(json).to eq(invoices: [])
      get_with_token(organization, preview_path, params)
      expect(json).to eq(original)
    end

    context "with other contracts" do
      let(:sibling) { create(:contract, organization:, customer:, started_at: contract.started_at) }
      let(:other) { create(:contract, organization:, customer: create(:customer, organization:), started_at: contract.started_at) }
      let(:other_card) { attach_card(other) }

      before do
        attach_card(sibling)
        other_card
      end

      it "bills sibling contracts once and leaves other customers alone" do
        post_with_token(organization, "/api/v2/contracts/bill", params.merge(external_ids: [contract.external_id]))
        expect(response).to have_http_status(:ok)
        expect(customer.billing_operations.completed.count).to eq(4)
        expect(other_card.billing_operations).to be_empty
      end
    end

    it "rejects the entire list when a contract belongs to another organization" do
      expect do
        post_with_token(organization, "/api/v2/contracts/bill", params.merge(external_ids: [contract.external_id, foreign_contract.external_id]))
      end.not_to change(Invoice, :count)
      expect(response).to be_v2_not_found_error("contract")
      expect(card.billing_operations).to be_empty
    end

    context "with a start date" do
      let(:params) { {start_on: "2026-01-01"} }

      it "rejects it because each card resumes from its own billing history" do
        bill
        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:details]).to eq([{field: "start_on", code: "value_is_invalid", meta: {}}])
      end
    end

    context "when the customer lock is busy" do
      before { allow(Customers::LockService).to receive(:call).and_raise(BaseLockService::FailedToAcquireLock) }

      it "returns the retryable concurrency error" do
        expect { bill }.not_to change(Invoice, :count)
        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:details]).to eq([{field: "base", code: "concurrency_conflict", meta: {}}])
      end
    end
  end
end
