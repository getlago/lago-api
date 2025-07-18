# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::DataApi::ChargesController, type: :request do # rubocop:disable RSpec/FilePath
  describe "GET /api/v1/data_api/charges/:id/forecasted_usage_amount" do
    subject { get_with_token(organization, "/api/v1/data_api/charges/#{charge_id}/forecasted_usage_amount", params) }

    let(:charge) do
      create(
        :standard_charge,
        plan:,
        billable_metric:,
        properties: {amount: "10"}
      )
    end

    let(:charge_id) { charge.id }
    let(:plan) { create(:plan, organization:, amount_cents: 1000) }
    let(:billable_metric) { create(:billable_metric, organization:) }
    let(:organization) { create(:organization) }
    let(:params) { {units:} }
    let(:units) { "1000" }

    let(:result) do
      BaseService::Result.new.tap do |result|
        result.charge_amount_cents = 10000
        result.subscription_amount_cents = 1000
        result.total_amount_cents = 11000
      end
    end

    before do
      allow(Charges::CalculatePriceService).to receive(:call).and_return(result)
    end

    context "when license is premium" do
      around { |test| lago_premium!(&test) }

      include_examples "requires API permission", "analytic", "read"

      context "when charge is found" do
        it "returns the forecasted usage amounts" do
          subject

          expect(response).to have_http_status(:success)

          expect(Charges::CalculatePriceService).to have_received(:call).with(units:, charge:, charge_filter: nil)
        end
      end

      context "when charge is not found" do
        let(:charge_id) { "notfound" }

        it "returns a not found error" do
          subject

          expect(response).to have_http_status(:not_found)
          expect(response.body).to include("charge_not_found")
        end
      end
    end

    context "when license is not premium" do
      it "returns forbidden status" do
        subject
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
