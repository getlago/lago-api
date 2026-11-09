# frozen_string_literal: true

require "rails_helper"

RSpec.describe Auth::GoogleService do
  before do
    ENV["GOOGLE_AUTH_CLIENT_ID"] = "client_id"
    ENV["GOOGLE_AUTH_CLIENT_SECRET"] = "client_secret"
  end

  describe ".call(:authorize_url)" do
    it "returns the authorize url" do
      request = Rack::Request.new(Rack::MockRequest.env_for("http://example.com"))
      result = described_class.call(:authorize_url, request)

      expect(result).to be_a(BaseResult)
      expect(result).to be_success
      expect(result.url).to include("https://accounts.google.com/o/oauth2/auth")
    end

    context "when google auth is not set up" do
      before do
        ENV["GOOGLE_AUTH_CLIENT_ID"] = nil
        ENV["GOOGLE_AUTH_CLIENT_SECRET"] = nil
      end

      it "returns a service failure" do
        request = Rack::Request.new(Rack::MockRequest.env_for("http://example.com"))
        result = described_class.call(:authorize_url, request)

        expect(result).not_to be_success
        expect(result.error.code).to eq("google_auth_missing_setup")
      end
    end

    it "returns no state secret when self-serve is off" do
      result = described_class.call(:authorize_url, Rack::Request.new(Rack::MockRequest.env_for("http://example.com")))

      expect(result.state_secret).to be_nil
    end

    context "when self-serve is enabled" do
      include_context "with self-serve enabled"

      it "binds the URL to the tab's secret and a PKCE challenge, with this region's callback" do
        allow(Rails.application.config).to receive(:lago_front_url).and_return("https://app.eu.getlago.com")

        result = described_class.call(:authorize_url, nil)
        query = Rack::Utils.parse_query(URI(result.url).query)
        code_verifier = Auth::GoogleOauthState.verify(state: query["state"], secret: result.state_secret)

        expect(code_verifier).to be_present
        expect(query).to include(
          "code_challenge" => Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false),
          "code_challenge_method" => "S256",
          "redirect_uri" => "https://app.eu.getlago.com/auth/google/callback"
        )
      end
    end
  end

  describe ".call(:claims)" do
    let(:authorizer) { instance_double(Google::Auth::UserAuthorizer) }
    let(:authorizer_response) { instance_double(Google::Auth::UserRefreshCredentials, id_token: "id_token") }
    let(:claims) { {"email" => "jane@getlago.com", "email_verified" => true, "hd" => "getlago.com"} }
    let(:issued) { Auth::GoogleOauthState.issue }

    before do
      allow(Google::Auth::UserAuthorizer).to receive(:new).and_return(authorizer)
      allow(authorizer).to receive(:get_credentials_from_code).and_return(authorizer_response)
      allow(Google::Auth::IDTokens).to receive(:verify_oidc).and_return(claims)
    end

    def claims_for(state: issued.state, state_secret: issued.secret)
      described_class.call(:claims, "code", state:, state_secret:)
    end

    it "redeems the code with the flow's code verifier and returns the claims" do
      expect(claims_for.claims).to eq(claims)
      expect(Google::Auth::UserAuthorizer).to have_received(:new).with(anything, anything, nil, anything, code_verifier: issued.code_verifier)
    end

    it "refuses an invalid state before any exchange" do
      expect(claims_for(state_secret: Auth::GoogleOauthState.issue.secret).error.messages).to eq(base: ["invalid_google_state"])
      expect(authorizer).not_to have_received(:get_credentials_from_code)
    end

    it "answers invalid_google_token for an ID token that fails verification" do
      [Google::Auth::IDTokens::ExpiredTokenError, Google::Auth::IDTokens::AudienceMismatchError].each do |error|
        allow(Google::Auth::IDTokens).to receive(:verify_oidc).and_raise(error)

        expect(claims_for.error.messages).to eq(base: ["invalid_google_token"])
      end
    end

    it "answers invalid_google_code for a code Google refuses" do
      allow(authorizer).to receive(:get_credentials_from_code).and_raise(Signet::AuthorizationError.new("bad code"))

      expect(claims_for.error.messages).to eq(base: ["invalid_google_code"])
    end

    it "answers google_auth_missing_setup without a client" do
      ENV["GOOGLE_AUTH_CLIENT_ID"] = nil

      expect(claims_for.error.code).to eq("google_auth_missing_setup")
    end
  end

  describe ".call(:login)" do
    let(:authorizer) { instance_double(Google::Auth::UserAuthorizer) }
    let(:oidc_verifier) { instance_double(Google::Auth::IDTokens) }
    let(:authorizer_response) { instance_double(Google::Auth::UserRefreshCredentials, id_token: "id_token") }
    let(:oidc_response) do
      {"email" => "foo@bar.com"}
    end

    before do
      allow(Google::Auth::UserAuthorizer).to receive(:new).and_return(authorizer)
      allow(authorizer).to receive(:get_credentials_from_code).and_return(authorizer_response)
      allow(Google::Auth::IDTokens).to receive(:verify_oidc).and_return(oidc_response)
    end

    it "answers invalid_google_token for an ID token that fails verification" do
      [Google::Auth::IDTokens::ExpiredTokenError, Google::Auth::IDTokens::AudienceMismatchError].each do |error|
        allow(Google::Auth::IDTokens).to receive(:verify_oidc).and_raise(error)

        expect(described_class.call(:login, "code").error.messages).to eq(base: ["invalid_google_token"])
      end
    end

    context "when user exists" do
      before do
        user = create(:user, email: "foo@bar.com", password: "foobar")
        create(:membership, :active, user:)
        allow(UserDevices::RegisterService).to receive(:call!)
      end

      it "registers the user device" do
        result = described_class.call(:login, "code")

        expect(UserDevices::RegisterService).to have_received(:call!).with(user: result.user)
      end

      it "logins the user" do
        result = described_class.call(:login, "code")

        expect(result).to be_a(BaseResult)
        expect(result).to be_success
        expect(result.user).to be_a(User)
        expect(result.token).to be_present

        decoded = Utils::AuthToken.decode(token: result.token)
        expect(decoded["login_method"]).to eq(Organizations::AuthenticationMethods::GOOGLE_OAUTH)
      end
    end

    context "when the stored email casing differs from the Google email" do
      let(:user) { create(:user, email: "Foo@Bar.com") }

      before do
        create(:membership, :active, user:)
        allow(UserDevices::RegisterService).to receive(:call!)
      end

      it "logs in the existing user" do
        result = described_class.call(:login, "code")

        expect(result).to be_success
        expect(result.user).to eq(user)
      end
    end

    context "when self-serve is enabled" do
      include_context "with self-serve enabled"

      let(:issued) { Auth::GoogleOauthState.issue }

      before do
        user = create(:user, email: "foo@bar.com")
        create(:membership, :active, user:)
        allow(UserDevices::RegisterService).to receive(:call!)
      end

      it "refuses a missing or invalid state before any exchange" do
        [{}, {state: issued.state, state_secret: Auth::GoogleOauthState.issue.secret}].each do |state_args|
          expect(described_class.call(:login, "code", **state_args).error.messages).to eq(base: ["invalid_google_state"])
        end

        expect(authorizer).not_to have_received(:get_credentials_from_code)
      end

      it "redeems the code with the flow's code verifier" do
        result = described_class.call(:login, "code", state: issued.state, state_secret: issued.secret)

        expect(result).to be_success
        expect(Google::Auth::UserAuthorizer).to have_received(:new).with(anything, anything, nil, anything, code_verifier: issued.code_verifier)
      end
    end

    context "when user does not exist" do
      it "returns a validation failure" do
        result = described_class.call(:login, "code")

        expect(result).not_to be_success
        expect(result.error.messages.values.flatten).to include("user_does_not_exist")
      end
    end

    context "when login method is not allowed" do
      let(:user) { create(:user, email: "foo@bar.com", password: "foobar") }
      let(:membership) { create(:membership, :active, user:) }

      before do
        membership.organization.disable_google_oauth_authentication!
      end

      it "returns a validation failure" do
        result = described_class.call(:login, "code")

        expect(result).not_to be_success
        expect(result.error.messages).to match(google_oauth: ["login_method_not_authorized"])
      end
    end

    context "when user does not have active memberships" do
      before do
        create(:user, email: "foo@bar.com")
      end

      it "returns a validation failure" do
        result = described_class.call(:login, "code")

        expect(result).not_to be_success
        expect(result.error.messages.values.flatten).to include("user_does_not_exist")
      end
    end

    context "when google auth is not set up" do
      before do
        ENV["GOOGLE_AUTH_CLIENT_ID"] = nil
        ENV["GOOGLE_AUTH_CLIENT_SECRET"] = nil
      end

      it "returns a service failure" do
        result = described_class.call(:login, "code")

        expect(result).not_to be_success
        expect(result.error.code).to eq("google_auth_missing_setup")
      end
    end

    context "with a self-serve user who never had an organization" do
      let(:oidc_response) { {"email" => "foo@bar.com", "email_verified" => true} }

      before do
        create(:user, :self_serve, email: "foo@bar.com")
        allow(UserDevices::RegisterService).to receive(:call!)
      end

      context "when self-serve is on" do
        include_context "with self-serve enabled"

        let(:issued) { Auth::GoogleOauthState.issue }

        def login
          described_class.call(:login, "code", state: issued.state, state_secret: issued.secret)
        end

        it "opens a Google session that needs an organization" do
          result = login

          expect(result).to be_success
          expect(result.user.needs_organization?).to be(true)
          expect(Utils::AuthToken.decode(token: result.token)["login_method"]).to eq(Organizations::AuthenticationMethods::GOOGLE_OAUTH)
        end

        it "refuses when Google did not verify the email" do
          [{"email" => "foo@bar.com", "email_verified" => false}, {"email" => "foo@bar.com"}].each do |claims|
            allow(Google::Auth::IDTokens).to receive(:verify_oidc).and_return(claims)

            expect(login.error.messages).to eq(base: ["user_does_not_exist"])
          end
        end
      end

      context "when self-serve is off" do
        it "refuses" do
          expect(described_class.call(:login, "code").error.messages).to eq(base: ["user_does_not_exist"])
        end
      end
    end
  end

  describe ".call(:register_user)" do
    let(:authorizer) { instance_double(Google::Auth::UserAuthorizer) }
    let(:oidc_verifier) { instance_double(Google::Auth::IDTokens) }
    let(:authorizer_response) { instance_double(Google::Auth::UserRefreshCredentials, id_token: "id_token") }
    let(:oidc_response) do
      {"email" => "foo@bar.com"}
    end

    before do
      create(:role, :admin)
      allow(Google::Auth::UserAuthorizer).to receive(:new).and_return(authorizer)
      allow(authorizer).to receive(:get_credentials_from_code).and_return(authorizer_response)
      allow(Google::Auth::IDTokens).to receive(:verify_oidc).and_return(oidc_response)
      allow(UserDevices::RegisterService).to receive(:call!)
    end

    it "registers the user device" do
      result = described_class.call(:register_user, "code", "Foobar")

      expect(UserDevices::RegisterService).to have_received(:call!).with(user: result.user, skip_log: true)
    end

    it "register the user" do
      result = described_class.call(:register_user, "code", "Foobar")

      expect(result).to be_a(BaseResult)
      expect(result).to be_success
      expect(result.user).to be_a(User)
      expect(result.token).to be_present

      decoded = Utils::AuthToken.decode(token: result.token)
      expect(decoded["login_method"]).to eq(Organizations::AuthenticationMethods::GOOGLE_OAUTH)
    end

    it "answers invalid_google_token for an ID token that fails verification" do
      [Google::Auth::IDTokens::ExpiredTokenError, Google::Auth::IDTokens::AudienceMismatchError].each do |error|
        allow(Google::Auth::IDTokens).to receive(:verify_oidc).and_raise(error)

        expect(described_class.call(:register_user, "code", "Foobar").error.messages).to eq(base: ["invalid_google_token"])
      end
    end

    context "when user already exists" do
      before { create(:user, email: "foo@bar.com") }

      it "returns a validation failure" do
        result = described_class.call(:register_user, "code", "FooBar")

        expect(result).not_to be_success
        expect(result.error.messages.values.flatten).to include("user_already_exists")
      end
    end

    context "when an existing user differs from the Google email only by casing" do
      before { create(:user, email: "Foo@Bar.com") }

      it "returns a validation failure without creating a duplicate user" do
        result = nil

        expect { result = described_class.call(:register_user, "code", "FooBar") }.not_to change(User, :count)
        expect(result).not_to be_success
        expect(result.error.messages.values.flatten).to include("user_already_exists")
      end
    end

    context "when signup is disabled" do
      before do
        ENV["LAGO_DISABLE_SIGNUP"] = "true"
      end

      after do
        ENV["LAGO_DISABLE_SIGNUP"] = nil
      end

      it "returns a forbidden error without creating a user" do
        result = nil

        expect { result = described_class.call(:register_user, "code", "FooBar") }.not_to change(User, :count)
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("signup_disabled")
      end
    end

    context "when google auth is not set up" do
      before do
        ENV["GOOGLE_AUTH_CLIENT_ID"] = nil
        ENV["GOOGLE_AUTH_CLIENT_SECRET"] = nil
      end

      it "returns a service failure" do
        result = described_class.call(:register_user, "code", "FooBar")

        expect(result).not_to be_success
        expect(result.error.code).to eq("google_auth_missing_setup")
      end
    end
  end

  describe ".call(:accept_invite)" do
    let(:invite) { create(:invite) }
    let(:authorizer) { instance_double(Google::Auth::UserAuthorizer) }
    let(:oidc_verifier) { instance_double(Google::Auth::IDTokens) }
    let(:authorizer_response) { instance_double(Google::Auth::UserRefreshCredentials, id_token: "id_token") }
    let(:oidc_response) do
      {"email" => invite.email}
    end

    before do
      invite
      allow(Google::Auth::UserAuthorizer).to receive(:new).and_return(authorizer)
      allow(authorizer).to receive(:get_credentials_from_code).and_return(authorizer_response)
      allow(Google::Auth::IDTokens).to receive(:verify_oidc).and_return(oidc_response)
    end

    it "answers invalid_google_token for an ID token that fails verification" do
      [Google::Auth::IDTokens::ExpiredTokenError, Google::Auth::IDTokens::AudienceMismatchError].each do |error|
        allow(Google::Auth::IDTokens).to receive(:verify_oidc).and_raise(error)

        expect(described_class.call(:accept_invite, "code", invite.token).error.messages).to eq(base: ["invalid_google_token"])
      end
    end

    it "accepts the invite" do
      result = described_class.call(:accept_invite, "code", invite.token)

      expect(result).to be_a(BaseResult)
      expect(result).to be_success
      expect(result.user).to be_a(User)
      expect(result.user.email).to eq(invite.email)
      expect(result.token).to be_present

      decoded = Utils::AuthToken.decode(token: result.token)
      expect(decoded["login_method"]).to eq(Organizations::AuthenticationMethods::GOOGLE_OAUTH)
    end

    context "when self-serve is enabled" do
      include_context "with self-serve enabled"

      let(:issued) { Auth::GoogleOauthState.issue }

      it "refuses a missing state, then accepts with the flow's code verifier" do
        expect(described_class.call(:accept_invite, "code", invite.token).error.messages).to eq(base: ["invalid_google_state"])
        expect(authorizer).not_to have_received(:get_credentials_from_code)

        result = described_class.call(:accept_invite, "code", invite.token, state: issued.state, state_secret: issued.secret)

        expect(result).to be_success
        expect(Google::Auth::UserAuthorizer).to have_received(:new).with(anything, anything, nil, anything, code_verifier: issued.code_verifier)
      end
    end

    context "when invite does not exists" do
      it "returns a not found failure" do
        result = described_class.call(:accept_invite, "code", "not_a_valid_token")

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("invite_not_found")
      end
    end

    context "when invite email is different from google email" do
      let(:oidc_response) do
        {"email" => "foo@bar.com"}
      end

      it "returns a validation failure" do
        result = described_class.call(:accept_invite, "code", invite.token)

        expect(result).not_to be_success
        expect(result.error.messages[:base]).to include("invite_email_mistmatch")
      end
    end

    context "when google auth is not set up" do
      before do
        ENV["GOOGLE_AUTH_CLIENT_ID"] = nil
        ENV["GOOGLE_AUTH_CLIENT_SECRET"] = nil
      end

      it "returns a service failure" do
        result = described_class.call(:accept_invite, "code", "FooBar")

        expect(result).not_to be_success
        expect(result.error.code).to eq("google_auth_missing_setup")
      end
    end
  end
end
