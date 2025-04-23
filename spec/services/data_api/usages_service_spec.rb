# frozen_string_literal: true

require "rails_helper"

RSpec.describe DataApi::UsagesService, type: :service do
  let(:service) { described_class.new(organization, **params) }
  let(:customer) { create(:customer, organization:) }
  let(:organization) { create(:organization) }
  let(:body_response) { File.read("spec/fixtures/lago_data_api/usages.json") }
  let(:params) { {time_granularity: "daily", start_of_period_dt: Date.current - 30.days} }
  let(:usage_json) do
    {
      "start_of_period_dt" => "2024-01-01",
      "end_of_period_dt" => "2024-01-31",
      "billable_metric_code" => "account_members",
      "amount_currency" => "EUR",
      "amount_cents" => 26600,
      "units" => 266
    }
  end

  before do
    stub_request(:get, "#{ENV["LAGO_DATA_API_URL"]}/usages/#{organization.id}/")
      .with(query: params)
      .to_return(status: 200, body: body_response, headers: {})
  end

  describe "#call" do
    subject(:service_call) { service.call }

    context "when licence is not premium" do
      it "returns usages" do
        expect(service_call).to be_success
        expect(service_call.usages.count).to eq(3)
        expect(service_call.usages.first).to eq(usage_json)
      end
    end

    context "when licence is premium" do
      around { |test| lago_premium!(&test) }

      it "returns usages" do
        expect(service_call).to be_success
        expect(service_call.usages.count).to eq(3)
        expect(service_call.usages.first).to eq(usage_json)
      end
    end
  end
end
