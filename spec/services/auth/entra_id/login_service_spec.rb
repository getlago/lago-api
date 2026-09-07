# frozen_string_literal: true

require "rails_helper"

RSpec.describe Auth::EntraId::LoginService, cache: :memory do
  let(:service) { described_class.new(code:, state:) }
  let(:entra_id_integration) { create(:entra_id_integration, domain: "bar.com") }
  let(:lago_http_client) { instance_double(LagoHttpClient::Client) }
  let(:entra_id_token_response) { {"access_token" => "access_token"} }
  let(:entra_id_userinfo_response) { {"email" => "foo@bar.com"} }
  let(:state) { SecureRandom.uuid }
  let(:code) { "code" }

  before do
    entra_id_integration

    Rails.cache.write(state, "foo@bar.com") if state.present?

    if entra_id_integration
      entra_id_integration.organization.premium_integrations << "entra_id"
      entra_id_integration.organization.save!
      entra_id_integration.organization.enable_entra_id_authentication!
    end

    allow(LagoHttpClient::Client).to receive(:new).and_return(lago_http_client)
    allow(lago_http_client).to receive(:post_url_encoded).and_return(entra_id_token_response)
    allow(lago_http_client).to receive(:get).and_return(entra_id_userinfo_response)
  end

  describe "#call", :premium do
    before { allow(UserDevices::RegisterService).to receive(:call!) }

    it "registers the user device" do
      result = service.call

      expect(UserDevices::RegisterService).to have_received(:call!).with(user: result.user)
    end

    it "creates user, membership and authenticate user" do
      result = service.call

      expect(result).to be_success
      expect(result.user.email).to eq("foo@bar.com")
      expect(result.token).to be_present

      decoded = Utils::AuthToken.decode(token: result.token)
      expect(decoded["login_method"]).to eq(Organizations::AuthenticationMethods::ENTRA_ID)
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
      let(:membership) { create(:membership, user:, organization: entra_id_integration.organization) }

      before { entra_id_integration.organization.disable_entra_id_authentication! }

      it "returns error" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error.messages).to match(entra_id: ["login_method_not_authorized"])
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

    context "when userinfo email is different from the state one" do
      let(:entra_id_userinfo_response) { {"email" => "foo@test.com"} }

      it "returns error" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error.messages.values.flatten).to include("entra_id_userinfo_error")
      end
    end

    context "when userinfo has no email but a matching preferred_username" do
      let(:entra_id_userinfo_response) { {"preferred_username" => "foo@bar.com"} }

      it "authenticates the user" do
        result = service.call

        expect(result).to be_success
        expect(result.user.email).to eq("foo@bar.com")
      end
    end

    context "when userinfo email casing differs from the state one" do
      let(:entra_id_userinfo_response) { {"email" => "Foo@Bar.com"} }

      it "authenticates the user" do
        result = service.call

        expect(result).to be_success
        expect(result.user.email).to eq("foo@bar.com")
      end
    end

    context "when userinfo has neither email nor preferred_username" do
      let(:entra_id_userinfo_response) { {} }

      it "returns error" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error.messages.values.flatten).to include("entra_id_userinfo_error")
      end
    end

    context "when user already exists" do
      let(:user) { create(:user, email: "foo@bar.com") }

      before { user }

      it "does not create a new user" do
        expect { service.call }.not_to change(User, :count)
      end
    end

    context "when membership already exists" do
      let(:user) { create(:user, email: "foo@bar.com") }
      let(:membership) { create(:membership, user:, organization: entra_id_integration.organization) }

      before { membership }

      it "does not create a new membership" do
        expect { service.call }.not_to change(Membership, :count)
      end
    end
  end
end
