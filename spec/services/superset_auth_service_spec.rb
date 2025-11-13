# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupersetAuthService do
  subject(:service) { described_class.new(organization:, dashboard_id:, user:) }

  let(:organization) { create(:organization, name: "Test Org") }
  let(:dashboard_id) { "2" }
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
    let(:guest_token) { "guest_token_789" }

    let(:login_response) { {access_token: access_token}.to_json }
    let(:csrf_response) { {result: csrf_token}.to_json }
    let(:guest_token_response) { {token: guest_token}.to_json }

    context "when authentication is successful" do
      before do
        stub_request(:post, "#{superset_url}/api/v1/security/login")
          .with(
            headers: {"Content-Type" => "application/json"},
            body: {
              username: superset_username,
              password: superset_password,
              provider: "db",
              refresh: true
            }.to_json
          )
          .to_return(
            status: 200,
            body: login_response,
            headers: {"Set-Cookie" => "session=abc123; Path=/; HttpOnly"}
          )

        stub_request(:get, "#{superset_url}/api/v1/security/csrf_token/")
          .with(
            headers: {
              "Authorization" => "Bearer #{access_token}",
              "Content-Type" => "application/json",
              "Referer" => "#{superset_url}/",
              "Cookie" => "session=abc123"
            }
          )
          .to_return(
            status: 200,
            body: csrf_response,
            headers: {"Set-Cookie" => "csrf_token=def456; Path=/"}
          )

        stub_request(:post, "#{superset_url}/api/v1/security/guest_token/")
          .with(
            headers: {
              "Authorization" => "Bearer #{access_token}",
              "Content-Type" => "application/json",
              "X-CSRFToken" => csrf_token,
              "Referer" => "#{superset_url}/",
              "Cookie" => "session=abc123; csrf_token=def456"
            },
            body: {
              resources: [{id: dashboard_id, type: "dashboard"}],
              rls: [],
              user: {
                first_name: "Test Org",
                last_name: "User",
                username: "guest_#{organization.id}"
              }
            }.to_json
          )
          .to_return(status: 200, body: guest_token_response)
      end

      it "returns success with tokens" do
        result = service.call

        expect(result).to be_success
        expect(result.guest_token).to eq(guest_token)
        expect(result.access_token).to eq(access_token)
      end
    end

    context "when custom user info is provided" do
      let(:user) do
        {
          first_name: "John",
          last_name: "Doe",
          username: "john.doe"
        }
      end

      before do
        stub_request(:post, "#{superset_url}/api/v1/security/login")
          .to_return(
            status: 200,
            body: login_response,
            headers: {"Set-Cookie" => "session=abc123"}
          )

        stub_request(:get, "#{superset_url}/api/v1/security/csrf_token/")
          .to_return(status: 200, body: csrf_response)

        stub_request(:post, "#{superset_url}/api/v1/security/guest_token/")
          .with(
            body: hash_including(
              user: {
                first_name: "John",
                last_name: "Doe",
                username: "john.doe"
              }
            )
          )
          .to_return(status: 200, body: guest_token_response)
      end

      it "uses the provided user info" do
        result = service.call

        expect(result).to be_success
        expect(result.guest_token).to eq(guest_token)
      end
    end

    context "when login fails" do
      before do
        stub_request(:post, "#{superset_url}/api/v1/security/login")
          .to_return(status: 401, body: {message: "Invalid credentials"}.to_json)
      end

      it "returns a service failure" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error.code).to eq("login_failed")
        expect(result.error.error_message).to include("Failed to login to Superset")
      end
    end

    context "when login returns no access token" do
      before do
        stub_request(:post, "#{superset_url}/api/v1/security/login")
          .to_return(status: 200, body: {}.to_json)
      end

      it "returns a service failure" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error.code).to eq("no_access_token")
        expect(result.error.error_message).to eq("No access token received from Superset")
      end
    end

    context "when CSRF token request fails" do
      before do
        stub_request(:post, "#{superset_url}/api/v1/security/login")
          .to_return(status: 200, body: login_response)

        stub_request(:get, "#{superset_url}/api/v1/security/csrf_token/")
          .to_return(status: 403, body: {message: "Forbidden"}.to_json)
      end

      it "returns a service failure" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error.code).to eq("csrf_failed")
        expect(result.error.error_message).to include("Failed to get CSRF token")
      end
    end

    context "when CSRF token response has no token" do
      before do
        stub_request(:post, "#{superset_url}/api/v1/security/login")
          .to_return(status: 200, body: login_response)

        stub_request(:get, "#{superset_url}/api/v1/security/csrf_token/")
          .to_return(status: 200, body: {}.to_json)
      end

      it "returns a service failure" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error.code).to eq("no_csrf_token")
        expect(result.error.error_message).to eq("No CSRF token received from Superset")
      end
    end

    context "when guest token request fails" do
      before do
        stub_request(:post, "#{superset_url}/api/v1/security/login")
          .to_return(status: 200, body: login_response)

        stub_request(:get, "#{superset_url}/api/v1/security/csrf_token/")
          .to_return(status: 200, body: csrf_response)

        stub_request(:post, "#{superset_url}/api/v1/security/guest_token/")
          .to_return(status: 500, body: {message: "Internal server error"}.to_json)
      end

      it "returns a service failure" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error.code).to eq("guest_token_failed")
        expect(result.error.error_message).to include("Failed to get guest token")
      end
    end

    context "when guest token response has no token" do
      before do
        stub_request(:post, "#{superset_url}/api/v1/security/login")
          .to_return(status: 200, body: login_response)

        stub_request(:get, "#{superset_url}/api/v1/security/csrf_token/")
          .to_return(status: 200, body: csrf_response)

        stub_request(:post, "#{superset_url}/api/v1/security/guest_token/")
          .to_return(status: 200, body: {}.to_json)
      end

      it "returns a service failure" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error.code).to eq("no_guest_token")
        expect(result.error.error_message).to eq("No guest token received from Superset")
      end
    end

    context "when login returns invalid JSON" do
      before do
        stub_request(:post, "#{superset_url}/api/v1/security/login")
          .to_return(status: 200, body: "invalid json")
      end

      it "returns a service failure" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error.code).to eq("invalid_response")
        expect(result.error.error_message).to include("Invalid JSON response from Superset login")
      end
    end

    context "when environment variables are missing" do
      before do
        stub_const("ENV", ENV.to_h.except("SUPERSET_URL"))
      end

      it "returns a service failure" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error.code).to eq("superset_auth_error")
        expect(result.error.error_message).to include("SUPERSET_URL environment variable not set")
      end
    end

    context "when SUPERSET_URL is invalid" do
      before do
        stub_const("ENV", ENV.to_h.merge("SUPERSET_URL" => "not a valid url"))
      end

      it "returns a service failure" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error.code).to eq("invalid_superset_url")
        expect(result.error.error_message).to include("Invalid Superset URL")
      end
    end
  end
end
