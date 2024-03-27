# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::Analytics::GrossRevenuesController, type: :request do
  describe "GET /analytics/gross_revenue" do
    let(:customer) { create(:customer, organization:) }
    let(:organization) { create(:organization) }

    context "when licence is premium" do
      around { |test| lago_premium!(&test) }

      it "returns the gross revenue" do
        get_with_token(
          organization,
          "/api/v1/analytics/gross_revenue"
        )

        aggregate_failures do
          expect(response).to have_http_status(:success)
          expect(json[:gross_revenues]).to eq([])
        end
      end
    end

    context "when licence is not premium" do
      it "returns the gross revenue" do
        get_with_token(
          organization,
          "/api/v1/analytics/gross_revenue"
        )

        expect(response).to have_http_status(:success)
        expect(json[:gross_revenues]).to eq([])
      end
    end
  end
end
