# frozen_string_literal: true

RSpec.describe Charges::ComputeForecastedUsageAmountsService, type: :service do
  subject(:service) { described_class.new(organization:) }

  let(:organization) { create(:organization, premium_integrations: %i[forecasted_usage]) }

  describe "#forecasted_charges_usages" do
    subject(:forecasted_usages) { service.send(:forecasted_charges_usages) }

    before do
      allow(DataApi::Usages::ForecastedChargesService).to receive(:call!).and_return(
        instance_double("DataApi::Usages::ForecastedChargesService", forecasted_charges_usages: [{"id" => 123}])
      )
    end

    it "calls DataApi::Usages::ForecastedChargesService with the correct arguments" do
      forecasted_usages
      expect(DataApi::Usages::ForecastedChargesService).to have_received(:call!).with(
        organization,
        limit: 1000,
        offset: 0
      )
    end

    it "returns the forecasted_charges_usages from the service response" do
      expect(forecasted_usages).to eq([{"id" => 123}])
    end
  end

  describe "#units_forecast_percentiles" do
    subject(:percentiles) { service.send(:units_forecast_percentiles) }

    it "returns the expected forecast percentile keys" do
      expect(percentiles).to eq([
        "units_forecast_10th_percentile",
        "units_forecast_50th_percentile",
        "units_forecast_90th_percentile"
      ])
    end
  end
end
