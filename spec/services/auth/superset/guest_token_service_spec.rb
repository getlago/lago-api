# frozen_string_literal: true

require "rails_helper"

RSpec.describe Auth::Superset::GuestTokenService do
  subject(:service) { described_class.new(organization:, dashboard_id:, user:) }

  let(:organization) { create(:organization, name: "Test Org") }
  let(:dashboard_id) { "42" }
  let(:user) { nil }

  let(:superset_url) { "http://localhost:8089" }
  let(:superset_username) { "admin" }
  let(:superset_password) { "admin" }

  before do
    stub_const("ENV", ENV.to_h.merge(
      "SUPERSET_URL" => superset_url,
      "SUPERSET_USERNAME" => superset_username,
      "SUPERSET_PASSWORD" => superset_password
    ))
  end

  describe ".call" do
    let(:access_token) { "access_token_123" }
    let(:csrf_token) { "csrf_token_456" }
    let(:guest_token) { "guest_token_for_dashboard" }

    let(:auth_response) { {access_token:}.to_json }
    let(:csrf_response) { {result: csrf_token}.to_json }
    let(:guest_token_response) { {token: guest_token}.to_json }

    def stub_auth_and_csrf
      stub_request(:post, "#{superset_url}/api/v1/security/login")
        .to_return(status: 200, body: auth_response, headers: {"Content-Type" => "application/json"})

      stub_request(:get, "#{superset_url}/api/v1/security/csrf_token/")
        .to_return(status: 200, body: csrf_response)
    end

    context "when the guest token is minted successfully" do
      before do
        stub_auth_and_csrf

        stub_request(:post, "#{superset_url}/api/v1/security/guest_token/")
          .with(body: hash_including(
            resources: [{id: dashboard_id, type: "dashboard"}],
            rls: [{clause: "organization_id = '#{organization.id}'"}]
          ))
          .to_return(status: 200, body: guest_token_response)
      end

      it "returns a fresh guest token scoped to the organization" do
        result = service.call

        expect(result).to be_success
        expect(result.guest_token).to eq(guest_token)
      end
    end

    context "when custom user info is provided" do
      let(:user) { {first_name: "John", last_name: "Doe", username: "john.doe"} }

      before do
        stub_auth_and_csrf

        stub_request(:post, "#{superset_url}/api/v1/security/guest_token/")
          .with(body: hash_including(user: {first_name: "John", last_name: "Doe", username: "john.doe"}))
          .to_return(status: 200, body: guest_token_response)
      end

      it "uses the provided user info" do
        result = service.call

        expect(result).to be_success
        expect(result.guest_token).to eq(guest_token)
      end
    end

    context "when authentication fails" do
      before do
        stub_request(:post, "#{superset_url}/api/v1/security/login")
          .to_return(status: 401, body: "Invalid credentials")
      end

      it "returns a service failure" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error.code).to eq("superset_auth_failed")
      end
    end

    context "when getting the CSRF token fails" do
      before do
        stub_request(:post, "#{superset_url}/api/v1/security/login")
          .to_return(status: 200, body: auth_response, headers: {"Content-Type" => "application/json"})

        stub_request(:get, "#{superset_url}/api/v1/security/csrf_token/")
          .to_return(status: 500, body: {message: "Internal error"}.to_json)
      end

      it "returns a service failure" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error.code).to eq("superset_csrf_failed")
      end
    end

    context "when Superset returns no guest token" do
      before do
        stub_auth_and_csrf

        stub_request(:post, "#{superset_url}/api/v1/security/guest_token/")
          .to_return(status: 200, body: {}.to_json)
      end

      it "returns a service failure" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error.code).to eq("superset_guest_token_failed")
        expect(result.error.error_message).to include("No guest token received from Superset")
      end
    end

    context "when the guest token request errors" do
      before do
        stub_auth_and_csrf

        stub_request(:post, "#{superset_url}/api/v1/security/guest_token/")
          .to_return(status: 500, body: {message: "Internal error"}.to_json)
      end

      it "returns a service failure" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error.code).to eq("superset_guest_token_failed")
      end
    end

    context "when environment variables are missing" do
      before do
        stub_const("ENV", ENV.to_h.except("SUPERSET_URL"))
      end

      it "returns a service failure" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error.code).to eq("superset_missing_configuration")
        expect(result.error.error_message).to include("SUPERSET_URL")
      end
    end
  end
end
