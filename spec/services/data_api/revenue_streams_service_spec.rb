# frozen_string_literal: true

require "rails_helper"

RSpec.describe DataApi::RevenueStreamsService, type: :service do
  let(:service) { described_class.new(organization, **params) }
  let(:customer) { create(:customer, organization:) }
  let(:organization) { create(:organization) }
  let(:body_response) { File.read("spec/fixtures/lago_data_api/revenue_streams.json") }
  let(:params) { {} }

  before do
    stub_request(:get, "#{ENV["LAGO_DATA_API_URL"]}/revenue_streams/#{organization.id}/")
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
        expect(service_call.revenue_streams.count).to eq(12)
        expect(service_call.revenue_streams.first).to eq(
          {
            "currency" => "EUR",
            "commitment_fee_amount_cents" => 0,
            "coupons_amount_cents" => 0,
            "from_date" => "2024-01-01",
            "gross_revenue_amount_cents" => 46256357,
            "in_advance_fee_amount_cents" => 0,
            "net_revenue_amount_cents" => 46256357,
            "one_off_fee_amount_cents" => 0,
            "organization_id" => "2537afc4-0e7c-4abb-89b7-d9b28c35780b",
            "subscription_fee_amount_cents" => 25681455,
            "to_date" => "2024-01-31",
            "usage_based_fee_amount_cents" => 20574902
          }
        )
      end
    end
  end
end
