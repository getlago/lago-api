# frozen_string_literal: true

require "rails_helper"

RSpec.describe DataApi::Usages::ForecastedChargesService, type: :service do
  let(:service) { described_class.new(organization, **params) }
  let(:customer) { create(:customer, organization:) }
  let(:organization) { create(:organization) }
  let(:body_response) { File.read("spec/fixtures/lago_data_api/usages_forecasted_charges.json") }
  let(:params) { {} }

  before do
    stub_request(:get, "#{ENV["LAGO_DATA_API_URL"]}/usages/#{organization.id}/forecasted/charges/")
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
        expect(service_call.forecasted_charges_usages.count).to eq(1)
        eq(
          {
            "organization_id" => "3fa85f64-5717-4562-b3fc-2c963f66afa6",
            "created_at" => "2025-06-27T06:46:28.300Z",
            "subscription_id" => "3fa85f64-5717-4562-b3fc-2c963f66afa6",
            "dt" => "2025-06-27",
            "charge_id" => "3fa85f64-5717-4562-b3fc-2c963f66afa6",
            "charge_filter_id" => "3fa85f64-5717-4562-b3fc-2c963f66afa6",
            "units_forecast_10th_percentile" => 0,
            "units_forecast_50th_percentile" => 0,
            "units_forecast_90th_percentile" => 0
          }
        )
      end
    end
  end

  describe "#action_path" do
    subject(:service_path) { service.send(:action_path) }

    it "returns the correct forecasted charges path" do
      expect(service_path).to eq("usages/#{organization.id}/forecasted/charges/")
    end
  end
end
