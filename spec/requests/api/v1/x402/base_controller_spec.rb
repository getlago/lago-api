# frozen_string_literal: true

require "rails_helper"

describe Api::V1::X402::BaseController, type: :controller do
  include ApiHelper

  controller(described_class) do
    def index
      render json: {ok: true}
    end

    private

    def resource_name
      "x402"
    end
  end

  let(:organization) { create(:organization, feature_flags:) }
  let(:feature_flags) { ["x402_payments"] }

  before do
    request.headers["Authorization"] = "Bearer #{organization.api_keys.first.value}"
    get :index
  end

  context "with a premium license", :premium do
    it "serves the request" do
      expect(json).to eq(ok: true)
    end

    context "when the x402_payments flag is off" do
      let(:feature_flags) { [] }

      it "answers 403" do
        expect(response).to have_http_status(:forbidden)
      end

      it "names the feature as unavailable" do
        expect(json[:code]).to eq("feature_unavailable")
      end
    end
  end

  context "without a premium license" do
    it "answers 403" do
      expect(response).to have_http_status(:forbidden)
    end

    it "names the feature as unavailable" do
      expect(json[:code]).to eq("feature_unavailable")
    end
  end
end
