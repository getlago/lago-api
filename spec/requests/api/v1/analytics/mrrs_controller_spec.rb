# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::Analytics::MrrsController, type: :request do # rubocop:disable RSpec/FilePath
  describe "GET /analytics/mrr" do
    let(:customer) { create(:customer, organization:) }
    let(:organization) { create(:organization) }

    context "when license is premium" do
      around { |test| lago_premium!(&test) }

      it "returns the mrr" do
        get_with_token(organization, "/api/v1/analytics/mrr")

        aggregate_failures do
          expect(response).to have_http_status(:success)

          month = DateTime.parse json[:mrrs].first[:month]

          expect(month).to eq(DateTime.current.beginning_of_month)
          expect(json[:mrrs].first[:currency]).to eq(nil)
          expect(json[:mrrs].first[:amount_cents]).to eq(nil)
        end
      end
    end

    context "when license is not premium" do
      it "returns forbidden status" do
        get_with_token(organization, "/api/v1/analytics/mrr")

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
