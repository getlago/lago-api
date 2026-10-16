# frozen_string_literal: true

require "rails_helper"

RSpec.describe Auth::Okta::AcceptInviteService, :premium, cache: :memory do
  subject(:service) { described_class.new(invite_token:, code:, state:) }

  let_it_be(:organization, refind: true) { create(:organization, premium_integrations: ["okta"]) }
  let(:okta_integration) { create(:okta_integration, domain: "bar.com", organization_name: "foo", organization:) }
  let(:invite) { create(:invite, email: "foo@bar.com", organization:) }
  let(:invite_token) { invite.token }
  let(:lago_http_client) { instance_double(LagoHttpClient::Client) }
  let(:okta_token_response) { {"access_token" => "access_token"} }
  let(:okta_userinfo_response) { {"email" => "foo@bar.com"} }
  let(:code) { "code" }
  let(:state) { SecureRandom.uuid }

  before do
    okta_integration
    invite_token

    organization.enable_okta_authentication!

    Rails.cache.write(state, "foo@bar.com") if state.present?

    allow(LagoHttpClient::Client).to receive(:new).and_return(lago_http_client)
    allow(lago_http_client).to receive(:post_url_encoded).and_return(okta_token_response)
    allow(lago_http_client).to receive(:get).and_return(okta_userinfo_response)
  end

  describe "#call" do
    it "creates user, membership, authenticate user and mark invite as accepted" do
      result = service.call

      expect(result).to be_success
      expect(result.user.email).to eq("foo@bar.com")
      expect(result.token).to be_present
      expect(invite.reload).to be_accepted

      decoded = Utils::AuthToken.decode(token: result.token)
      expect(decoded["login_method"]).to eq(Organizations::AuthenticationMethods::OKTA)
      expect(decoded["sso_organization_id"]).to eq(okta_integration.organization_id)
      expect(decoded["sso_issuer"]).to eq(okta_integration.sso_issuer)
    end

    context "when the email domain belongs to another organization's integration" do
      let(:other_organization) { create(:organization, premium_integrations: ["okta"]) }
      let(:okta_integration) { create(:okta_integration, domain: "bar.com", organization_name: "foo", organization: other_organization) }

      before { other_organization.enable_okta_authentication! }

      it "refuses the invite and keeps it pending" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error.messages).to eq({okta: ["login_method_not_authorized"]})
        expect(invite.reload).to be_pending
        expect(User.find_by(email: "foo@bar.com")).to be_nil
      end

      context "when the invited organization's integration has the same issuer" do
        before { create(:okta_integration, domain: "baz.com", organization_name: "foo", organization:) }

        it "accepts the invite" do
          result = service.call

          expect(result).to be_success
          expect(invite.reload).to be_accepted
          expect(Utils::AuthToken.decode(token: result.token)["sso_organization_id"]).to eq(other_organization.id)
        end

        context "when the integration's organization does not allow the login method" do
          before { other_organization.disable_okta_authentication! }

          it "refuses the invite and keeps it pending" do
            result = service.call

            expect(result).not_to be_success
            expect(result.error.messages).to eq({okta: ["login_method_not_authorized"]})
            expect(invite.reload).to be_pending
          end
        end
      end
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
      let(:okta_integration) { nil }

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

    context "when okta userinfo email is different from the state one" do
      let(:okta_userinfo_response) { {"email" => "foo@test.com"} }

      it "returns error" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error.messages.values.flatten).to include("okta_userinfo_error")
      end
    end

    context "when the invited email belongs to a member of another organization" do
      let(:user) { create(:user, email: "foo@bar.com") }

      before { create(:membership, user:) }

      it "adds the user to the invited organization" do
        result = service.call

        expect(result).to be_success
        expect(result.user).to eq(user)
        expect(invite.reload).to be_accepted
        expect(user.memberships.active.where(organization:)).to exist
      end
    end
  end
end
