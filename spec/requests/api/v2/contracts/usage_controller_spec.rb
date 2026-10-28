# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::Contracts::UsageController do
  describe "GET /api/v2/contracts/:external_id/current_usage", :bullet do
    subject { get_with_token(organization, "/api/v2/contracts/#{external_id}/current_usage", params) }

    let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
    let(:customer) { create(:customer, organization:, timezone: "UTC", currency: "EUR") }
    let(:contract) { create(:contract, organization:, customer:, started_at: Time.zone.parse("2027-01-01")) }
    let(:external_id) { contract.external_id }
    let(:params) { {} }
    let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: :count_agg) }
    let(:product_category) { create(:product_category, organization:) }
    let(:metered_product) { create(:product, organization:, billable_metric:, product_category:) }
    let(:metered_rate_card) { create(:rate_card, organization:, product: metered_product, currency: "EUR") }
    let(:fixed_rate_card) do
      create(:rate_card, organization:, product: create(:product, :fixed, :standalone, organization:), currency: "EUR")
    end
    let(:rate_card_entries) { json[:current_usage][:rate_cards].index_by { |entry| entry[:rate_card_code] } }

    around { |example| travel_to(Time.zone.parse("2027-02-10 12:00:00")) { example.run } }

    before do
      [[metered_rate_card, nil, "2"], [fixed_rate_card, 3, "10"]].each do |rate_card, units, amount|
        create(:contract_rate_card, organization:, contract:, rate_card:, units:,
          effective_date: Date.new(2027, 1, 1), billing_anchor_date: Date.new(2027, 1, 1))
        create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2027-01-01"),
          rate_properties: {"amount" => amount})
      end
      create(:event, organization:, customer:, external_subscription_id: contract.external_id,
        code: billable_metric.code, timestamp: Time.zone.parse("2027-02-05"))
    end

    include_examples "requires API permission", "customer_usage", "read"

    it "returns each card on its open window" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:current_usage].except(:rate_cards)).to eq(
        external_contract_id: contract.external_id,
        external_customer_id: customer.external_id,
        currency: "EUR",
        amount_cents: 3200,
        taxes_amount_cents: 0,
        total_amount_cents: 3200
      )
      expect(rate_card_entries[metered_rate_card.code]).to eq(
        rate_card_code: metered_rate_card.code,
        rate_card_name: metered_rate_card.name,
        product_code: metered_product.code,
        product_name: metered_product.name,
        product_category_code: product_category.code,
        product_category_name: product_category.name,
        product_filter_code: nil,
        product_filter_name: nil,
        invoice_display_name: metered_product.name,
        product_type: "metered",
        billable_metric_code: billable_metric.code,
        billing_timing: "arrears",
        from_datetime: "2027-02-01T00:00:00.000000Z",
        to_datetime: "2027-02-28T23:59:59.999999Z",
        rate_phase_code: nil,
        rate_phase_name: nil,
        rate_source: "rate",
        rate_model: "standard",
        rate_properties: {amount: "2"},
        units: "1.0",
        events_count: 1,
        amount_cents: 200
      )
      expect(rate_card_entries[fixed_rate_card.code]).to eq(
        rate_card_code: fixed_rate_card.code,
        rate_card_name: fixed_rate_card.name,
        product_code: fixed_rate_card.product.code,
        product_name: fixed_rate_card.product.name,
        product_category_code: nil,
        product_category_name: nil,
        product_filter_code: nil,
        product_filter_name: nil,
        invoice_display_name: fixed_rate_card.product.name,
        product_type: "fixed",
        billable_metric_code: nil,
        billing_timing: "arrears",
        from_datetime: "2027-02-01T00:00:00.000000Z",
        to_datetime: "2027-02-28T23:59:59.999999Z",
        rate_phase_code: nil,
        rate_phase_name: nil,
        rate_source: "rate",
        rate_model: "standard",
        rate_properties: {amount: "10"},
        units: "3.0",
        events_count: 0,
        amount_cents: 3000
      )
    end

    context "with an intro phase overriding the rate" do
      before do
        contract_rate_card = contract.applied_rate_cards.find_by!(rate_card: metered_rate_card)
        create(:rate_phase, :contract_level, organization:, contract_rate_card:, plan_rate_card: nil, code: "intro",
          name: "Intro", position: 1, billing_interval_cycle_count: 2,
          rate_override: create(:rate_override, organization:, rate_model: "package",
            rate_properties: {"amount" => "1", "package_size" => 1, "free_units" => 0}))
      end

      it "returns the phase's rate" do
        subject

        expect(rate_card_entries[metered_rate_card.code]).to include(
          rate_phase_code: "intro", rate_phase_name: "Intro", rate_source: "phase_override",
          rate_model: "package", rate_properties: {amount: "1", package_size: 1, free_units: 0}, amount_cents: 100
        )
      end
    end

    context "with a product type filter" do
      let(:params) { {product_type: "fixed"} }

      it "returns the matching cards and their totals only" do
        subject

        expect(json[:current_usage][:rate_cards].map { |entry| entry[:rate_card_code] }).to eq([fixed_rate_card.code])
        expect(json[:current_usage]).to include(amount_cents: 3000, total_amount_cents: 3000)
      end
    end

    context "with a card scoped to a product filter" do
      let(:eu_filter) do
        create(:product_filter, organization:, product: metered_product, name: "EU region", invoice_display_name: "API calls (EU)")
      end
      let(:eu_rate_card) do
        create(:rate_card, organization:, product: metered_product, product_filter: eu_filter, currency: "EUR")
      end
      let(:params) { {product_filter_code: eu_filter.code} }

      before do
        region = create(:billable_metric_filter, organization:, billable_metric:, key: "region", values: %w[eu us])
        create(:product_filter_value, organization:, product_filter: eu_filter, billable_metric_filter: region, value: "eu")
        create(:contract_rate_card, organization:, contract:, rate_card: eu_rate_card,
          effective_date: Date.new(2027, 1, 1), billing_anchor_date: Date.new(2027, 1, 1))
        create(:rate_card_rate, organization:, rate_card: eu_rate_card, effective_from: Time.zone.parse("2027-01-01"),
          rate_properties: {"amount" => "2"})
        create(:event, organization:, customer:, external_subscription_id: contract.external_id,
          code: billable_metric.code, timestamp: Time.zone.parse("2027-02-06"), properties: {region: "eu"})
      end

      it "returns the filter's card with the filter's names" do
        subject

        expect(json[:current_usage][:rate_cards].sole).to include(
          rate_card_code: eu_rate_card.code, product_code: metered_product.code,
          product_filter_code: eu_filter.code, product_filter_name: "EU region", invoice_display_name: "API calls (EU)",
          units: "1.0", amount_cents: 200
        )
      end
    end

    context "with an unknown product type" do
      let(:params) { {product_type: "usage"} }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq(product_type: ["value_is_invalid"])
      end
    end

    context "with taxes" do
      before do
        create(:customer_applied_tax, customer:, tax: create(:tax, organization:, rate: 20))
      end

      it "applies them" do
        subject

        expect(json[:current_usage]).to include(amount_cents: 3200, taxes_amount_cents: 640, total_amount_cents: 3840)
      end

      context "when apply_taxes is false" do
        let(:params) { {apply_taxes: "false"} }

        it "leaves them out" do
          subject

          expect(json[:current_usage]).to include(taxes_amount_cents: 0, total_amount_cents: 3200)
        end
      end
    end

    # The error renders no entry, so the eager loading the entries need goes unused.
    context "when the customer's tax provider cannot resolve the taxes", bullet: {n_plus_one_query: true, unused_eager_loading: false} do
      let(:integration) { create(:anrok_integration, organization:) }

      before do
        create(:anrok_customer, integration:, customer:)
        stub_request(:post, "https://api.nango.dev/v1/anrok/draft_invoices")
          .to_return(body: File.read(Rails.root.join("spec/fixtures/integration_aggregator/taxes/invoices/failure_response.json")))
      end

      it "answers with the tax error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to include(code: "validation_errors", error_details: {tax_error: ["taxDateTooFarInFuture: Service failure"]})
      end
    end

    # As above, the error renders no entry, so the eager loading the entries need goes unused.
    context "when the customer's tax provider throttles the request", bullet: {n_plus_one_query: true, unused_eager_loading: false} do
      let(:integration) { create(:anrok_integration, organization:) }

      before do
        create(:anrok_customer, integration:, customer:)
        allow(Throttling).to receive(:for).with(:anrok).and_return(instance_double(Throttling::Base, check: false))
      end

      it "answers with a too many provider requests error" do
        subject

        expect(response).to have_http_status(:too_many_requests)
        expect(json).to eq(
          status: 429,
          error: "Too Many Provider Requests",
          code: "too_many_provider_requests",
          error_details: {provider_name: "anrok", message: "Service anrok is not available. Try again later."}
        )
      end
    end

    context "with a pending replacement" do
      before do
        create(:contract, :pending, organization:, customer:, external_id: contract.external_id)
      end

      it "returns the usage of the active contract" do
        subject

        expect(json[:current_usage][:rate_cards].size).to eq(2)
      end
    end

    context "when the contract is pending" do
      let(:contract) { create(:contract, :pending, organization:, customer:) }

      it "returns no usage" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:current_usage]).to include(rate_cards: [], amount_cents: 0, total_amount_cents: 0)
      end
    end

    context "when the contract is terminated" do
      let(:contract) do
        create(:contract, :terminated, organization:, customer:, started_at: Time.zone.parse("2027-01-01"),
          ended_at: Time.zone.parse("2027-02-01"))
      end

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("contract")
      end
    end

    context "with an unknown external id" do
      let(:external_id) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("contract")
      end
    end

    context "with a contract of another organization" do
      let(:customer) { create(:customer, timezone: "UTC", currency: "EUR") }
      let(:contract) do
        create(:contract, organization: customer.organization, customer:, started_at: Time.zone.parse("2027-01-01"))
      end

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("contract")
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
