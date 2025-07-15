# frozen_string_literal: true

require "rails_helper"

RSpec.describe DataApi::Usages::ForecastedService, type: :service do
  let(:service) { described_class.new(organization, **params) }
  let(:customer) { create(:customer, organization:) }
  let(:organization) { create(:organization) }
  let(:body_response) { File.read("spec/fixtures/lago_data_api/usages_forecasted.json") }
  let(:params) { {} }

  before do
    stub_request(:get, "#{ENV["LAGO_DATA_API_URL"]}/usages/#{organization.id}/forecasted/")
      .to_return(status: 200, body: body_response, headers: {})
  end

  describe "#call" do
    subject(:service_call) { service.call }

    context "when licence is not premium" do
      it "returns an error" do
        expect(service_call).not_to be_success
        expect(service_call.error.code).to eq("feature_unavailable")
      end
    end

    context "when licence is premium" do
      around { |test| lago_premium!(&test) }

      it "returns expected forecasted usage" do
        expect(service_call).to be_success
        expect(service_call.forecasted_usages.count).to eq(2)
        expect(service_call.forecasted_usages.first).to eq(
          {
            "organization_id" => "2537afc4-0e7c-4abb-89b7-d9b28c35780b",
            "start_of_period_dt" => "2025-06-23",
            "end_of_period_dt" => "2025-06-23",
            "amount_currency" => "EUR",
            "units" => 100,
            "amount_cents" => 1000,
            "units_forecast_10th_percentile" => 20,
            "units_forecast_50th_percentile" => 30,
            "units_forecast_90th_percentile" => 50,
            "amount_cents_forecast_10th_percentile" => 200,
            "amount_cents_forecast_50th_percentile" => 300,
            "amount_cents_forecast_90th_percentile" => 500
          }
        )
      end
    end
  end

  describe "#action_path" do
    subject(:action_path) { service.send(:action_path) }

    let(:params) { {} }

    it "returns the correct API path for the organization" do
      expect(action_path).to eq("usages/#{organization.id}/forecasted/")
    end
  end
end
