# frozen_string_literal: true

require "rails_helper"

RSpec.describe DataApi::RevenueStreams::CustomersService, type: :service do
  let(:service) { described_class.new(organization, **params) }
  let(:customer) { create(:customer, organization:) }
  let(:organization) { create(:organization) }
  let(:body_response) { File.read("spec/fixtures/lago_data_api/revenue_streams_customers.json") }
  let(:params) { {} }

  before do
    stub_request(:get, "#{ENV["LAGO_DATA_API_URL"]}/revenue_streams/#{organization.id}/customers")
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

      it "returns expected revenue streams" do
        expect(service_call).to be_success
        expect(service_call.revenue_streams_customers.count).to eq(4)
        expect(service_call.revenue_streams_customers.first).to eq(
          {
            "amount_currency" => "EUR",
            "customer_id" => "e4676e50-1234-4606-bcdb-42effbc2b635",
            "customer_name" => "Penny",
            "external_customer_id" => "2537afc4-1234-4abb-89b7-d9b28c35780b",
            "gross_revenue_amount_cents" => 124628322,
            "gross_revenue_share" => 0.1185,
            "net_revenue_amount_cents" => 124628322,
            "net_revenue_share" => 0.1185,
            "organization_id" => "c0047031-41b6-4386-a10b-0a36f787c84f"
          }
        )
      end
    end
  end
end
