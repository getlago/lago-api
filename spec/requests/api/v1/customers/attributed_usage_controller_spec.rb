# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::Customers::AttributedUsageController, clickhouse: {clean_before: true} do
  include_context "with clickhouse availability"

  around { |example| travel_to(Time.zone.parse("2026-09-15 12:00:00")) { example.run } }

  let(:organization) { create(:organization, clickhouse_events_store: true, feature_flags: ["account_tree"]) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, interval: :monthly, amount_currency: "EUR") }
  let(:started_at) { Time.zone.parse("2026-08-01") }
  let(:subscription) { create(:subscription, :calendar, customer:, plan:, started_at:, subscription_at: started_at) }

  let(:tokens_metric) { create(:sum_billable_metric, organization:, code: "tokens", field_name: "tokens") }
  let(:requests_metric) { create(:billable_metric, organization:, code: "requests", aggregation_type: "count_agg") }
  let(:tokens_charge) { create(:standard_charge, plan:, billable_metric: tokens_metric, code: "tokens", properties: {"amount" => "0.5"}) }
  let(:requests_charge) { create(:standard_charge, plan:, billable_metric: requests_metric, code: "requests", properties: {"amount" => "2"}) }

  let(:events) do
    [
      {code: "tokens", value: 1000, labels: {"team" => "eng", "model" => "opus"}, properties: {"model" => "opus"}},
      {code: "tokens", value: 500, labels: {"team" => "eng", "model" => "sonnet"}, properties: {"model" => "sonnet"}},
      {code: "tokens", value: 2000, labels: {"team" => "data", "model" => "opus"}, properties: {"model" => "opus"}},
      {code: "requests", value: 1, labels: {"team" => "eng"}},
      {code: "tokens", value: 100, labels: {}}
    ]
  end

  def create_event(code:, value:, labels:, properties: {})
    Clickhouse::EventsEnriched.create!(
      organization_id: organization.id,
      external_subscription_id: subscription.external_id,
      code:,
      timestamp: Time.zone.parse("2026-09-10"),
      transaction_id: SecureRandom.uuid,
      properties:,
      attribution_labels: labels,
      value: value.to_s,
      decimal_value: value
    )
  end

  before do
    create(:usage_attribution_type, organization:, code: "team")
    create(:flat_usage_attribution_type, organization:, code: "model")
    tokens_charge
    requests_charge
    events.each { create_event(**it) }
  end

  describe "GET /api/v1/customers/:customer_external_id/attributed_usage" do
    subject { get_with_token(organization, "/api/v1/customers/#{customer_external_id}/attributed_usage", params) }

    let(:customer_external_id) { customer.external_id }
    let(:params) { {external_subscription_id: subscription.external_id, group_by: "team"} }

    include_examples "requires API permission", "attributed_usage", "read"

    it "returns the attributed usage of the level, in units" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:attributed_usage]).to include(
        lago_subscription_id: subscription.id,
        external_subscription_id: subscription.external_id,
        group_by: "team",
        basis: "units",
        from_datetime: "2026-09-01T00:00:00Z",
        to_datetime: "2026-09-30T23:59:59Z",
        currency: "EUR"
      )
      expect(json[:attributed_usage][:rows].map { it.slice(:value, :rank, :events_count, :amount_cents) }).to eq(
        [
          {value: "eng", rank: 1, events_count: 3, amount_cents: nil},
          {value: "data", rank: 2, events_count: 1, amount_cents: nil}
        ]
      )
      expect(json[:attributed_usage][:rows].first[:charges_usage]).to match_array(
        [
          {
            lago_charge_id: tokens_charge.id,
            charge_code: "tokens",
            billable_metric_code: "tokens",
            lago_charge_filter_id: nil,
            charge_filter_values: nil,
            charge_filter_invoice_display_name: nil,
            units: "1500.0",
            amount_cents: nil,
            precise_amount_cents: nil,
            events_count: 2
          },
          {
            lago_charge_id: requests_charge.id,
            charge_code: "requests",
            billable_metric_code: "requests",
            lago_charge_filter_id: nil,
            charge_filter_values: nil,
            charge_filter_invoice_display_name: nil,
            units: "1.0",
            amount_cents: nil,
            precise_amount_cents: nil,
            events_count: 1
          }
        ]
      )
      expect(json[:attributed_usage][:unattributed]).to include(events_count: 1)
      expect(json[:attributed_usage][:totals]).to include(events_count: 5)
      expect(json[:meta]).to eq(current_page: 1, next_page: nil, prev_page: nil, total_pages: 1, total_count: 2)
    end

    context "with the amount basis and selected charges" do
      let(:params) do
        {external_subscription_id: subscription.external_id, group_by: "team", basis: "amount", charge_codes: ["tokens"]}
      end

      it "returns the amounts of the selected charges" do
        subject

        rows = json[:attributed_usage][:rows]
        expect(rows.map { it.slice(:value, :amount_cents, :precise_amount_cents) }).to eq(
          [
            {value: "data", amount_cents: 100_000, precise_amount_cents: "100000.0"},
            {value: "eng", amount_cents: 75_000, precise_amount_cents: "75000.0"}
          ]
        )
        expect(rows.flat_map { it[:charges_usage] }.pluck(:charge_code).uniq).to eq(["tokens"])
        expect(json[:attributed_usage][:totals]).to include(amount_cents: 180_000)
      end
    end

    context "with a split charge" do
      let(:billable_metric_filter) { create(:billable_metric_filter, billable_metric: tokens_metric, key: "model", values: %w[opus sonnet]) }
      let(:charge_filter) { create(:charge_filter, charge: tokens_charge, invoice_display_name: "Opus", properties: {"amount" => "1"}) }
      let(:params) do
        {
          external_subscription_id: subscription.external_id,
          group_by: "team",
          charge_codes: ["tokens"],
          split_charge_code: "tokens"
        }
      end

      before { create(:charge_filter_value, charge_filter:, billable_metric_filter:, values: ["opus"]) }

      it "returns one cell per filter and one for the default price" do
        subject

        cells = json[:attributed_usage][:rows].find { it[:value] == "eng" }[:charges_usage]
        expect(cells.map { it.slice(:lago_charge_filter_id, :charge_filter_values, :charge_filter_invoice_display_name, :units) }).to eq(
          [
            {lago_charge_filter_id: charge_filter.id, charge_filter_values: {model: ["opus"]}, charge_filter_invoice_display_name: "Opus", units: "1000.0"},
            {lago_charge_filter_id: nil, charge_filter_values: nil, charge_filter_invoice_display_name: nil, units: "500.0"}
          ]
        )
      end
    end

    context "with filters" do
      let(:params) do
        {external_subscription_id: subscription.external_id, group_by: "team", filters: {model: %w[opus haiku]}}
      end

      it "narrows the usage to the matching labels" do
        subject

        expect(json[:attributed_usage][:rows].map { it.slice(:value, :events_count) }).to eq(
          [{value: "data", events_count: 1}, {value: "eng", events_count: 1}]
        )
      end
    end

    context "with a custom window" do
      let(:params) do
        {
          external_subscription_id: subscription.external_id,
          group_by: "team",
          from_datetime: "2026-09-11T00:00:00Z",
          to_datetime: "2026-09-14T00:00:00Z"
        }
      end

      it "reads the window" do
        subject

        expect(json[:attributed_usage]).to include(from_datetime: "2026-09-11T00:00:00Z", to_datetime: "2026-09-14T00:00:00Z")
        expect(json[:attributed_usage][:rows]).to eq([])
        expect(json[:meta]).to eq(current_page: 0, next_page: nil, prev_page: nil, total_pages: 0, total_count: 0)
      end
    end

    context "with pagination" do
      let(:params) { {external_subscription_id: subscription.external_id, group_by: "team", page: 2, per_page: 1} }

      it "returns the requested page" do
        subject

        expect(json[:attributed_usage][:rows].map { it.slice(:value, :rank) }).to eq([{value: "data", rank: 2}])
        expect(json[:meta]).to eq(current_page: 2, next_page: nil, prev_page: 1, total_pages: 2, total_count: 2)
      end
    end

    context "with invalid parameters" do
      let(:params) do
        {external_subscription_id: subscription.external_id, group_by: "team", from_datetime: "yesterday", page: 0, per_page: 101}
      end

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq(
          from_datetime: ["invalid_date"],
          page: ["value_is_out_of_range"],
          per_page: ["value_is_out_of_range"]
        )
      end
    end

    context "when the query service rejects the request" do
      let(:params) { {external_subscription_id: subscription.external_id, group_by: "team", basis: "euros"} }

      it "returns its validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq(basis: ["value_is_invalid"])
      end
    end

    context "when the query exceeds the ClickHouse limits" do
      before do
        allow(UsageAttributions::QueryService).to receive(:call)
          .and_return(UsageAttributions::QueryService::Result.new.service_failure!(code: "too_many_groups", message: "TOO_MANY_ROWS"))
      end

      it "asks to narrow the request" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(status: 422, error: "Unprocessable Entity", code: "too_many_groups")
      end
    end

    context "with an unknown charge code" do
      let(:params) { {external_subscription_id: subscription.external_id, group_by: "team", charge_codes: %w[tokens unknown]} }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("charge")
      end
    end

    context "with an unknown split charge code" do
      let(:params) { {external_subscription_id: subscription.external_id, group_by: "team", split_charge_code: "unknown"} }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("charge")
      end
    end

    context "with an unknown customer" do
      let(:customer_external_id) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("customer")
      end
    end

    context "with a terminated subscription" do
      let(:subscription) do
        create(:subscription, :calendar, customer:, plan:, started_at:, subscription_at: started_at,
          status: :terminated, terminated_at: Time.zone.parse("2026-09-12"))
      end

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("subscription")
      end
    end

    context "when the feature flag is disabled" do
      let(:organization) { create(:organization, clickhouse_events_store: true) }

      it "returns a forbidden error" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end
  end
end
