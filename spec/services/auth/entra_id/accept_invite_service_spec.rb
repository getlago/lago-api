# frozen_string_literal: true

require "rails_helper"

RSpec.describe Auth::EntraId::AcceptInviteService, :premium, cache: :memory do
  subject(:service) { described_class.new(invite_token:, code:, state:) }

  let(:organization) { create(:organization, premium_integrations: ["entra_id"]) }
  let(:entra_id_integration) { create(:entra_id_integration, domain: "bar.com", organization:) }
  let(:invite) { create(:invite, email: "foo@bar.com", organization:) }
  let(:invite_token) { invite.token }
  let(:lago_http_client) { instance_double(LagoHttpClient::Client) }
  let(:entra_id_token_response) { {"access_token" => "access_token"} }
  let(:entra_id_userinfo_response) { {"email" => "foo@bar.com"} }
  let(:code) { "code" }
  let(:state) { SecureRandom.uuid }

  before do
    entra_id_integration
    invite_token

    organization.enable_entra_id_authentication!

    Rails.cache.write(state, "foo@bar.com") if state.present?

    allow(LagoHttpClient::Client).to receive(:new).and_return(lago_http_client)
    allow(lago_http_client).to receive(:post_url_encoded).and_return(entra_id_token_response)
    allow(lago_http_client).to receive(:get).and_return(entra_id_userinfo_response)
  end

  describe "#call" do
    it "creates user, membership, authenticate user and mark invite as accepted" do
      result = service.call

      expect(result).to be_success
      expect(result.user.email).to eq("foo@bar.com")
      expect(result.token).to be_present
      expect(invite.reload).to be_accepted

      decoded = Utils::AuthToken.decode(token: result.token)
      expect(decoded["login_method"]).to eq(Organizations::AuthenticationMethods::ENTRA_ID)
    end

    context "when code is not provided" do
      let(:code) { nil }

      it "returns an error" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error.messages).to eq({base: ["code_not_found"]})
      end
    end

    context "when state is not provided" do
      let(:state) { nil }

      it "returns an error" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error.messages).to eq({base: ["state_not_found"]})
      end
    end

    context "when state is not found" do
      before do
        Rails.cache.clear
      end

      it "returns error" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error.messages.values.flatten).to include("state_not_found")
      end
    end

    context "when domain is not configured with an integration" do
      let(:entra_id_integration) { nil }

      it "returns error" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error.messages.values.flatten).to include("domain_not_configured")
      end
    end

    context "when pending invite does not exists" do
      let(:invite) { create(:invite, email: "foo@bar.com", status: :accepted) }

      it "returns a failure result" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error.messages.values.flatten).to include("invite_not_found")
      end
    end

    context "when userinfo email is different from the state one" do
      let(:entra_id_userinfo_response) { {"email" => "foo@test.com"} }

      it "returns error" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error.messages.values.flatten).to include("entra_id_userinfo_error")
      end
    end
  end
end
