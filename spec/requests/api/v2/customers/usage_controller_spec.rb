# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::Customers::UsageController do
  subject(:request_usage) do
    get_with_token(organization, "/api/v2/customers/#{customer.external_id}/current_usage", params)
  end

  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:customer) { create(:customer, organization:, currency: "USD", timezone: "UTC") }
  let(:contract) { create(:contract, organization:, customer:, status: :active, started_at: Time.utc(2026, 8, 1)) }
  let(:params) { {external_contract_id: contract.external_id, apply_taxes: false} }
  let(:metric) { create(:billable_metric, organization:, aggregation_type: :count_agg) }
  let(:product) { create(:product, organization:, billable_metric: metric) }
  let(:rate_card) { create(:rate_card, organization:, product:, currency: "USD") }
  let(:card) do
    create(:contract_rate_card, organization:, contract:, rate_card:,
      effective_date: Date.new(2026, 8, 1), billing_anchor_date: Date.new(2026, 8, 1))
  end
  let(:rate) do
    create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 8, 1), rate_properties: {"amount" => "2"})
  end

  around { |example| travel_to(Time.utc(2026, 8, 20, 12)) { example.run } }

  before do
    rate
    card
    create(:event, organization:, customer:, external_subscription_id: contract.external_id,
      code: metric.code, timestamp: Time.utc(2026, 8, 10), properties: {region: "eu"})
    create(:event, organization:, customer:, external_subscription_id: contract.external_id,
      code: metric.code, timestamp: Time.utc(2026, 8, 20), properties: {region: "us"})
  end

  include_examples "requires API permission", "customer_usage", "read"

  it "returns contract usage without persisting billing state" do
    expect { request_usage }.to not_change(BillingSegment, :count).and not_change(Invoice, :count).and not_change(Fee, :count)

    expect(response).to have_http_status(:ok)
    expect(json[:customer_usage]).to include(
      from_datetime: "2026-08-01T00:00:00Z", to_datetime: "2026-08-31T23:59:59Z", issuing_date: "2026-08-31",
      currency: "USD", amount_cents: 400, taxes_amount_cents: 0, total_amount_cents: 400
    )
    usage = json[:customer_usage][:products_usage].sole
    expect(usage[:product]).to include(lago_id: product.id, code: product.code)
    expect(usage[:billable_metric][:code]).to eq(metric.code)
    expect(usage).to include(units: "2.0", amount_cents: 400, filters: [])
  end

  it "aggregates through the period end while excluding other periods and contracts" do
    [Time.utc(2026, 7, 31, 23, 59, 59), Time.utc(2026, 8, 21), Time.utc(2026, 9, 1)].each do |timestamp|
      create(:event, organization:, customer:, external_subscription_id: contract.external_id, code: metric.code, timestamp:)
    end
    create(:event, organization:, customer:, external_subscription_id: "another-contract", code: metric.code, timestamp: Time.current)

    request_usage

    expect(response).to have_http_status(:ok)
    expect(json[:customer_usage][:amount_cents]).to eq(600)
  end

  context "with product filters" do
    let(:region) { create(:billable_metric_filter, organization:, billable_metric: metric, key: "region", values: %w[eu us]) }
    let(:filter) { create(:product_filter, organization:, product:, invoice_display_name: "Europe") }

    before { create(:product_filter_value, organization:, product_filter: filter, billable_metric_filter: region, value: "eu") }

    it "returns the product filter values and default bucket" do
      request_usage

      expect(response).to have_http_status(:ok)
      filters = json[:customer_usage][:products_usage].sole[:filters]
      expect(filters.map { |item| [item[:lago_id], item[:values], item[:amount_cents]] }).to match_array([
        [filter.id, {region: ["eu"]}, 200], [nil, nil, 200]
      ])
      expect(filters.find { |item| item[:lago_id] == filter.id }[:invoice_display_name]).to eq("Europe")
    end
  end

  context "with multiple products" do
    let(:other_product) { create(:product, organization:) }

    before do
      other_rate_card = create(:rate_card, organization:, product: other_product, currency: "USD")
      create(:rate_card_rate, organization:, rate_card: other_rate_card, effective_from: Time.utc(2026, 8, 1))
      create(:contract_rate_card, organization:, contract:, rate_card: other_rate_card,
        effective_date: Date.new(2026, 8, 1), billing_anchor_date: Date.new(2026, 8, 1))
      create(:event, organization:, customer:, external_subscription_id: contract.external_id,
        code: other_product.billable_metric.code, timestamp: Time.utc(2026, 8, 10))
    end

    it "keeps products with no legacy charge separate" do
      request_usage

      expect(response).to have_http_status(:ok)
      expect(json[:customer_usage][:products_usage].map { |usage| usage[:product][:lago_id] }).to match_array([product.id, other_product.id])
    end

    context "when filtering by product code" do
      let(:params) { super().merge(product_code: product.code) }

      it "only computes the selected product" do
        request_usage

        expect(response).to have_http_status(:ok)
        expect(json[:customer_usage][:products_usage].sole[:product][:lago_id]).to eq(product.id)
        expect(json[:customer_usage][:amount_cents]).to eq(400)
      end
    end
  end

  context "with a rate change in the current cycle" do
    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 8, 15), rate_properties: {"amount" => "3"})
    end

    it "prices both segments without counting events twice" do
      request_usage

      expect(response).to have_http_status(:ok)
      expect(json[:customer_usage][:amount_cents]).to eq(500)
      expect(json[:customer_usage][:products_usage].map { |usage| usage[:amount_cents] }).to match_array([200, 300])
    end
  end

  context "with taxes" do
    let(:params) { {external_contract_id: contract.external_id} }

    before { create(:tax, :applied_to_billing_entity, organization:, rate: 20) }

    it "applies taxes by default" do
      request_usage

      expect(response).to have_http_status(:ok)
      expect(json[:customer_usage]).to include(amount_cents: 400, taxes_amount_cents: 80, total_amount_cents: 480)
    end
  end

  context "with a persisted current-period snapshot" do
    before do
      create(:billing_segment, organization:, customer:, contract:, contract_rate_card: card, rate_card_rate: rate,
        currency: "USD", rate_properties: {"amount" => "7"},
        cycle_started_at: Time.utc(2026, 8, 1), started_at: Time.utc(2026, 8, 1),
        ended_at: BillingSegment.inclusive_end(Time.utc(2026, 9, 1)))
    end

    it "builds current usage from the schedule instead of the persisted segment" do
      request_usage

      expect(response).to have_http_status(:ok)
      expect(json[:customer_usage][:amount_cents]).to eq(400)
    end
  end

  context "with a non-UTC customer timezone" do
    let(:customer) { create(:customer, organization:, currency: "USD", timezone: "America/New_York") }

    it "uses the customer's local calendar boundaries" do
      request_usage

      expect(response).to have_http_status(:ok)
      expect(json[:customer_usage]).to include(
        from_datetime: "2026-08-01T00:00:00-04:00", to_datetime: "2026-08-31T23:59:59-04:00"
      )
    end
  end

  context "with only fixed products" do
    let(:product) { create(:product, :fixed, organization:) }

    it "returns zero metered usage" do
      request_usage

      expect(response).to have_http_status(:ok)
      expect(json[:customer_usage]).to include(amount_cents: 0, products_usage: [])
    end
  end

  context "with an unknown product filter parameter" do
    let(:params) { super().merge(product_code: "unknown") }

    it "returns product not found" do
      request_usage

      expect(response).to be_not_found_error("product")
    end
  end

  context "with no configured rate" do
    let(:rate) { nil }

    it "returns rate not found instead of failing the request" do
      request_usage

      expect(response).to be_not_found_error("rate")
    end
  end

  context "with another organization's customer" do
    it "does not expose their usage" do
      other_customer = create(:customer)
      get_with_token(organization, "/api/v2/customers/#{other_customer.external_id}/current_usage", params)

      expect(response).to be_not_found_error("customer")
    end
  end

  context "without a contract identifier" do
    let(:params) { {apply_taxes: false} }

    it "returns no active contract" do
      request_usage

      expect(response).to have_http_status(:method_not_allowed)
      expect(json[:code]).to eq("no_active_contract")
    end
  end

  context "with a pending contract" do
    before { contract.update!(status: :pending) }

    it "returns no active contract" do
      request_usage

      expect(response).to have_http_status(:method_not_allowed)
      expect(json[:code]).to eq("no_active_contract")
    end
  end

  context "with another customer's contract" do
    let(:params) { {external_contract_id: create(:contract, organization:).external_id} }

    it "does not expose its usage" do
      request_usage

      expect(response).to have_http_status(:method_not_allowed)
      expect(json[:code]).to eq("no_active_contract")
    end
  end

  context "with an unknown customer" do
    it "returns a customer not found error" do
      get_with_token(organization, "/api/v2/customers/unknown/current_usage", params)

      expect(response).to be_not_found_error("customer")
    end
  end

  context "without product catalog enabled", product_catalog: false do
    let(:organization) { create(:organization) }

    it "rejects the request" do
      request_usage

      expect(response).to have_http_status(:forbidden)
    end
  end
end
