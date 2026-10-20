# frozen_string_literal: true

require "rails_helper"

# The v1 controller serves /api/v2 through the v1 fallback routes.
RSpec.describe Api::V1::Customers::AttributedUsageController, clickhouse: {clean_before: true} do # rubocop:disable RSpec/SpecFilePathFormat
  include_context "with clickhouse availability"

  around { |example| travel_to(Time.zone.parse("2026-09-15 12:00:00")) { example.run } }

  let(:organization) { create(:organization, clickhouse_events_store: true, feature_flags: ["account_tree"]) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, interval: :monthly, amount_currency: "EUR") }
  let(:started_at) { Time.zone.parse("2026-08-01") }
  let(:subscription) { create(:subscription, :calendar, customer:, plan:, started_at:, subscription_at: started_at) }
  let(:tokens_metric) { create(:sum_billable_metric, organization:, code: "tokens", field_name: "tokens") }
  let(:tokens_charge) { create(:standard_charge, plan:, billable_metric: tokens_metric, code: "tokens", properties: {"amount" => "0.5"}) }

  let(:events) do
    [
      {code: "tokens", value: 1000, labels: {"team" => "eng"}},
      {code: "tokens", value: 2000, labels: {"team" => "data"}}
    ]
  end

  def create_event(code:, value:, labels:)
    Clickhouse::EventsEnriched.create!(
      organization_id: organization.id,
      external_subscription_id: subscription.external_id,
      code:,
      timestamp: Time.zone.parse("2026-09-10"),
      transaction_id: SecureRandom.uuid,
      properties: {},
      attribution_labels: labels,
      value: value.to_s,
      decimal_value: value
    )
  end

  before do
    create(:usage_attribution_type, organization:, code: "team")
    tokens_charge
    events.each { create_event(**it) }
  end

  describe "GET /api/v2/customers/:customer_external_id/attributed_usage" do
    subject { get_with_token(organization, "/api/v2/customers/#{customer_external_id}/attributed_usage", params) }

    let(:customer_external_id) { customer.external_id }
    let(:params) { {external_subscription_id: subscription.external_id, group_by: "team"} }

    context "without page params" do
      it "returns the attributed usage as a beta endpoint" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:attributed_usage][:rows].map { it[:value] }).to eq(%w[data eng])
        expect(response.headers["X-Lago-Endpoint-Status"]).to eq("beta")
      end
    end

    context "with per_page at its own maximum" do
      let(:params) { {external_subscription_id: subscription.external_id, group_by: "team", per_page: 100} }

      it "returns the attributed usage" do
        subject

        expect(response).to have_http_status(:success)
      end
    end

    context "with per_page above its own maximum" do
      let(:params) { {external_subscription_id: subscription.external_id, group_by: "team", per_page: 101} }

      it "returns a validation error on per_page" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq(per_page: ["value_is_out_of_range"])
      end
    end

    context "with per_page above the organization page size limit" do
      let(:organization) do
        create(:organization, clickhouse_events_store: true, feature_flags: ["account_tree"], pagination_max_page_size: 50)
      end
      let(:params) { {external_subscription_id: subscription.external_id, group_by: "team", per_page: 51} }

      it "returns a validation error on per_page" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq(per_page: ["value_is_out_of_range"])
      end
    end

    context "with an unknown customer and per_page above its own maximum" do
      let(:customer_external_id) { "unknown" }
      let(:params) { {external_subscription_id: subscription.external_id, group_by: "team", per_page: 101} }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("customer")
      end
    end

    context "with an invalid datetime and out of range page params" do
      let(:params) do
        {external_subscription_id: subscription.external_id, group_by: "team", from_datetime: "yesterday", page: 0, per_page: 101}
      end

      it "returns all the validation errors together" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq(
          from_datetime: ["invalid_date"],
          page: ["value_is_out_of_range"],
          per_page: ["value_is_out_of_range"]
        )
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
