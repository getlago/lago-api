# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::DataApi::UsagesController, type: :request do # rubocop:disable RSpec/FilePath
  describe "GET /analytics/usage" do
    subject { get_with_token(organization, "/api/v1/analytics/usage", params) }

    let(:customer) { create(:customer, organization:) }
    let(:organization) { create(:organization) }
    let(:params) { {} }

    before do
      allow(DataApi::UsagesService).to receive(:call).and_call_original
    end

    context "when license is premium" do
      around { |test| lago_premium!(&test) }

      include_examples "requires API permission", "analytic", "read"

      it "returns the usage" do
        subject

        expect(response).to have_http_status(:success)

        expect(json[:usages].first[:currency]).to eq(nil)
        expect(json[:usages].first[:amount_cents]).to eq(nil)
        expect(DataApi::UsagesService).to have_received(:call).with(organization, currency: nil, months: nil)
      end
    end

    context "when license is not premium" do
      include_examples "requires API permission", "analytic", "read"

      it "returns the usage" do
        subject

        expect(response).to have_http_status(:success)

        expect(json[:usages].first[:currency]).to eq(nil)
        expect(json[:usages].first[:amount_cents]).to eq(nil)
        expect(DataApi::UsagesService).to have_received(:call).with(organization, currency: nil, months: nil)
      end
    end
  end
end
