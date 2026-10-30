# frozen_string_literal: true

require "rails_helper"

RSpec.describe Auth::Okta::LoginService, cache: :memory do
  let(:service) { described_class.new(code:, state:) }
  let(:okta_integration) { create(:okta_integration, domain: "bar.com", organization_name: "foo") }
  let(:lago_http_client) { instance_double(LagoHttpClient::Client) }
  let(:okta_token_response) { {"access_token" => "access_token"} }
  let(:okta_userinfo_response) { {"email" => "foo@bar.com"} }
  let(:state) { SecureRandom.uuid }
  let(:code) { "code" }

  before do
    okta_integration

    Rails.cache.write(state, "foo@bar.com") if state.present?

    if okta_integration
      okta_integration.organization.premium_integrations << "okta"
      okta_integration.organization.save!
      okta_integration.organization.enable_okta_authentication!
    end

    allow(LagoHttpClient::Client).to receive(:new).and_return(lago_http_client)
    allow(lago_http_client).to receive(:post_url_encoded).and_return(okta_token_response)
    allow(lago_http_client).to receive(:get).and_return(okta_userinfo_response)
  end

  describe "#call", :premium do
    before { allow(UserDevices::RegisterService).to receive(:call!) }

    it "registers the user device" do
      result = service.call

      expect(UserDevices::RegisterService).to have_received(:call!).with(user: result.user)
    end

    it "protects the Okta requests against private addresses" do
      service.call

      expect(LagoHttpClient::Client).to have_received(:new)
        .with("https://foo.okta.com/oauth2/v1/token", block_private_addresses: true)
      expect(LagoHttpClient::Client).to have_received(:new)
        .with("https://foo.okta.com/oauth2/v1/userinfo", block_private_addresses: true)
    end

    it "creates user, membership and authenticate user" do
      result = service.call

      expect(result).to be_success
      expect(result.user.email).to eq("foo@bar.com")
      expect(result.token).to be_present

      decoded = Utils::AuthToken.decode(token: result.token)
      expect(decoded["login_method"]).to eq(Organizations::AuthenticationMethods::OKTA)
      expect(decoded["sso_organization_id"]).to eq(okta_integration.organization_id)
      expect(decoded["sso_issuer"]).to eq("foo.okta.com")
    end

    context "when code is not provided" do
      let(:code) { nil }

      it "returns error" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error.messages).to eq({base: ["code_not_found"]})
      end
    end

    context "when state is not provided" do
      let(:state) { nil }

      it "returns error" do
        result = service.call
        expect(result).not_to be_success
        expect(result.error.messages).to eq({base: ["state_not_found"]})
      end
    end

    context "when the login method is not allowed" do
      let(:user) { create(:user, email: "foo@bar.com") }
      let(:membership) { create(:membership, user:, organization: okta_integration.organization) }

      before { okta_integration.organization.disable_okta_authentication! }

      it "returns error" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error.messages).to match(okta: ["login_method_not_authorized"])
      end
    end

    context "when the integration organization disallows the login method but another membership allows it" do
      let(:user) { create(:user, email: "foo@bar.com") }

      let(:other_organization) { create(:organization, authentication_methods: %w[email_password okta]) }

      before do
        create(:membership, user:, organization: okta_integration.organization)
        create(:membership, user:, organization: other_organization)
        okta_integration.organization.disable_okta_authentication!
      end

      it "refuses the login" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error.messages).to match(okta: ["login_method_not_authorized"])
        expect(result.token).to be_nil
      end

      context "when both organizations keep cross-organization SSO sessions" do
        before do
          okta_integration.organization.enable_feature_flag!(:sso_cross_organization_sessions)
          other_organization.enable_feature_flag!(:sso_cross_organization_sessions)
        end

        it "logs the user in" do
          result = service.call

          expect(result).to be_success
          expect(result.token).to be_present
          expect(other_organization.accessible_by_session?(**Utils::AuthToken.decode(token: result.token).slice("login_method", "sso_organization_id", "sso_issuer").symbolize_keys)).to be(true)
        end
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

    context "when okta userinfo email is different from the state one" do
      let(:okta_userinfo_response) { {"email" => "foo@test.com"} }

      it "returns error" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error.messages.values.flatten).to include("okta_userinfo_error")
      end
    end

    context "when userinfo email casing differs from the state one" do
      let(:okta_userinfo_response) { {"email" => "Foo@Bar.com"} }

      it "authenticates the user" do
        result = service.call

        expect(result).to be_success
        expect(result.user.email).to eq("foo@bar.com")
      end
    end

    context "when userinfo has no email" do
      let(:okta_userinfo_response) { {} }

      it "returns error" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error.messages.values.flatten).to include("okta_userinfo_error")
      end
    end

    context "when an existing user differs from the typed email only by casing" do
      let!(:user) { create(:user, email: "Foo@Bar.com") }

      before { create(:membership, user:, organization: okta_integration.organization) }

      it "signs in the existing user instead of creating a new one" do
        result = nil

        expect { result = service.call }.not_to change(User, :count)
        expect(result.user).to eq(user)
      end
    end

    context "when an existing user of another organization differs from the typed email only by casing" do
      before { create(:membership, user: create(:user, email: "Foo@Bar.com")) }

      it "refuses the login without creating a new user" do
        result = nil

        expect { result = service.call }.not_to change(User, :count)
        expect(result).not_to be_success
        expect(result.error.messages[:okta]).to eq(["login_method_not_authorized"])
      end
    end

    context "when users exist with the typed casing and with another casing" do
      let!(:exact_user) { create(:user, email: "foo@bar.com") }

      before do
        create(:user, email: "FOO@bar.com", created_at: 1.year.ago)
        create(:membership, user: exact_user, organization: okta_integration.organization)
      end

      it "signs in the user with the exact casing" do
        expect(service.call.user).to eq(exact_user)
      end
    end

    context "when user already exists" do
      let(:user) { create(:user, email: "foo@bar.com") }

      before { create(:membership, user:, organization: okta_integration.organization) }

      it "does not create a new user" do
        expect { service.call }.not_to change(User, :count)
      end
    end

    context "when an existing user is not a member of the integration organization" do
      let(:user) { create(:user, email: "foo@bar.com") }

      before { create(:membership, user:) }

      it "refuses the login without adding the user to the organization" do
        result = nil

        expect { result = service.call }.not_to change(Membership, :count)
        expect(result).not_to be_success
        expect(result.error.messages[:okta]).to eq(["login_method_not_authorized"])
        expect(result.token).to be_nil
      end

      context "when the integration organization keeps cross-organization SSO sessions" do
        before { okta_integration.organization.enable_feature_flag!(:sso_cross_organization_sessions) }

        it "logs the user in and adds them to the organization" do
          result = service.call

          expect(result).to be_success
          expect(result.token).to be_present
          expect(user.memberships.active.where(organization: okta_integration.organization)).to exist
        end
      end
    end

    context "when an existing user only belongs to an organization whose integration has the same issuer" do
      let(:user) { create(:user, email: "foo@bar.com") }
      let(:other_organization) { create(:organization, authentication_methods: %w[email_password okta]) }

      before do
        create(:okta_integration, organization: other_organization, domain: "baz.com", organization_name: "foo")
        create(:membership, user:, organization: other_organization)
      end

      it "logs the user in, as after accepting that organization's invite" do
        result = service.call

        expect(result).to be_success
        expect(result.token).to be_present
      end
    end

    context "when an existing user's membership of the integration organization is revoked" do
      let(:user) { create(:user, email: "foo@bar.com") }

      before { create(:membership, :revoked, user:, organization: okta_integration.organization) }

      it "refuses the login" do
        result = service.call

        expect(result).not_to be_success
        expect(result.token).to be_nil
      end
    end

    context "when membership already exists" do
      let(:user) { create(:user, email: "foo@bar.com") }
      let(:membership) { create(:membership, user:, organization: okta_integration.organization) }

      before { membership }

      it "does not create a new membership" do
        expect { service.call }.not_to change(Membership, :count)
      end
    end
  end
end
