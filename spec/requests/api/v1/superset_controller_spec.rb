# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::SupersetController do # rubocop:disable RSpec/FilePath
  describe "POST /superset/guest_token" do
    subject { post_with_token(organization, "/api/v1/superset/guest_token", params) }

    let(:organization) { create(:organization) }
    let(:params) { {dashboard_id: "2"} }

    let(:result) do
      BaseService::Result.new.tap do |result|
        result.guest_token = "guest_token_123"
        result.access_token = "access_token_456"
      end
    end

    before do
      allow(SupersetAuthService).to receive(:call).and_return(result)
    end

    include_examples "requires API permission", "analytic", "write"

    context "when the request is successful" do
      it "returns the guest token" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:guest_token]).to eq("guest_token_123")
        expect(json[:access_token]).to eq("access_token_456")
        expect(SupersetAuthService).to have_received(:call).with(
          organization: organization,
          dashboard_id: "2",
          user: nil
        )
      end
    end

    context "when user parameters are provided" do
      let(:params) do
        {
          dashboard_id: "2",
          user: {
            first_name: "John",
            last_name: "Doe",
            username: "john.doe"
          }
        }
      end

      it "passes user info to the service" do
        subject

        expect(response).to have_http_status(:success)
        expect(SupersetAuthService).to have_received(:call).with(
          organization: organization,
          dashboard_id: "2",
          user: {
            "first_name" => "John",
            "last_name" => "Doe",
            "username" => "john.doe"
          }
        )
      end
    end

    context "when dashboard_id is missing" do
      let(:params) { {} }

      it "passes nil dashboard_id to the service" do
        subject

        expect(SupersetAuthService).to have_received(:call).with(
          organization: organization,
          dashboard_id: nil,
          user: nil
        )
      end
    end

    context "when the service fails" do
      let(:result) do
        BaseService::Result.new.tap do |result|
          result.service_failure!(code: "login_failed", message: "Failed to login to Superset")
        end
      end

      it "returns an error response" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json[:error]).to eq("login_failed")
        expect(json[:message]).to eq("Failed to login to Superset")
      end
    end
  end
end
