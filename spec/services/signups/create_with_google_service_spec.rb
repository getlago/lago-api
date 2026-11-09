# frozen_string_literal: true

require "rails_helper"

RSpec.describe Signups::CreateWithGoogleService do
  subject(:result) { described_class.call(code: "code", state: issued.state, state_secret: issued.secret) }

  let(:issued) { Auth::GoogleOauthState.issue }
  let(:authorizer) { instance_double(Google::Auth::UserAuthorizer) }
  let(:claims) { {"email" => "jane@getlago.com", "email_verified" => true, "hd" => "getlago.com"} }

  include_context "with self-serve enabled"

  before do
    freeze_time
    stub_const("ENV", ENV.to_h.merge("GOOGLE_AUTH_CLIENT_ID" => "client_id", "GOOGLE_AUTH_CLIENT_SECRET" => "client_secret"))
    allow(Google::Auth::UserAuthorizer).to receive(:new).and_return(authorizer)
    allow(authorizer).to receive(:get_credentials_from_code)
      .and_return(instance_double(Google::Auth::UserRefreshCredentials, id_token: "id_token"))
    allow(Google::Auth::IDTokens).to receive(:verify_oidc) { claims }
    allow(UserDevices::RegisterService).to receive(:call!)
  end

  def code_for(response)
    response.error.messages[:base]
  end

  context "with a company Workspace account and no Lago user" do
    it "creates a user with no organization, ready for Step 3" do
      expect { result }.to change(User, :count).by(1).and not_change(Organization, :count)

      expect(result.user).to have_attributes(email: "jane@getlago.com", self_serve_verified_at: Time.current)
      expect(result.user.memberships).to be_empty
      expect(result.user.needs_organization?).to be(true)
      expect(Utils::AuthToken.decode(token: result.token)["login_method"]).to eq(Organizations::AuthenticationMethods::GOOGLE_OAUTH)
    end

    it "sends no verification email and logs no new device" do
      result

      expect(Signups::DeliverVerificationJob).not_to have_been_enqueued
      expect(SendEmailJob).not_to have_been_enqueued
      expect(UserDevices::RegisterService).to have_received(:call!).with(user: result.user, skip_log: true)
    end

    it "takes the email lock of the address" do
      allow(Users::EmailLockService).to receive(:call).and_call_original

      result

      expect(Users::EmailLockService).to have_received(:call).with(email: "jane@getlago.com")
    end
  end

  describe "refusals" do
    it "refuses when self-serve is off or signups are paused" do
      stub_const("ENV", ENV.to_h.merge("LAGO_SELF_SERVE_ENABLED" => "false"))
      expect(result.error.code).to eq("self_serve_disabled")

      stub_const("ENV", ENV.to_h.merge("LAGO_SELF_SERVE_ENABLED" => "true", "LAGO_DISABLE_SIGNUP" => "true"))
      expect(described_class.call(code: "code", state: issued.state, state_secret: issued.secret).error.code).to eq("signup_disabled")
    end

    it "refuses an invalid state before any exchange" do
      response = described_class.call(code: "code", state: issued.state, state_secret: Auth::GoogleOauthState.issue.secret)

      expect(code_for(response)).to eq(["invalid_google_state"])
      expect(authorizer).not_to have_received(:get_credentials_from_code)
    end

    it "refuses accounts that are not company Workspace accounts, and creates nothing" do
      [
        {"email" => "jane@getlago.com", "email_verified" => false, "hd" => "getlago.com"},
        {"email" => "jane@getlago.com", "hd" => "getlago.com"},
        {"email" => "jane@gmail.com", "email_verified" => true},
        {"email" => "jane@getlago.com", "email_verified" => true},
        {"email" => "jane@getlago.com", "email_verified" => true, "hd" => "other.com"},
        {"email" => "jane@mailinator.com", "email_verified" => true, "hd" => "mailinator.com"}
      ].each do |account|
        allow(Google::Auth::IDTokens).to receive(:verify_oidc).and_return(account)

        response = described_class.call(code: "code", state: issued.state, state_secret: issued.secret)

        expect(code_for(response)).to eq(["company_google_account_required"])
      end

      expect(User.count).to eq(0)
    end
  end

  describe "existing users" do
    it "logs in an active member, even with a personal Google account" do
      member = create(:user, email: "jane@gmail.com")
      create(:membership, user: member)
      allow(Google::Auth::IDTokens).to receive(:verify_oidc).and_return("email" => "jane@gmail.com", "email_verified" => true)

      expect { result }.not_to change { [User.count, Organization.count] }
      expect(result.user).to eq(member)
    end

    it "logs in the user whose stored email differs only by case" do
      member = create(:user, email: "Jane@GetLago.com")
      create(:membership, user: member)

      expect(result.user).to eq(member)
    end

    it "logs in a self-serve user who still needs an organization" do
      orgless = create(:user, :self_serve, email: "jane@getlago.com")

      expect(result.user).to eq(orgless)
      expect(result.user.needs_organization?).to be(true)
    end

    it "refuses a member whose organizations disable Google" do
      member = create(:user, email: "jane@getlago.com")
      create(:membership, user: member, organization: create(:organization, authentication_methods: %w[email_password]))

      expect(result.error.messages).to eq(google_oauth: ["login_method_not_authorized"])
    end

    context "when Google did not verify the email" do
      let(:claims) { {"email" => "jane@getlago.com", "email_verified" => false, "hd" => "getlago.com"} }

      context "with an active member" do
        let(:member) { create(:user, email: "jane@getlago.com") }

        before { create(:membership, user: member) }

        it "logs them in, as Google login does" do
          expect(result.user).to eq(member)
        end
      end

      context "with a self-serve user who still needs an organization" do
        before { create(:user, :self_serve, email: "jane@getlago.com") }

        it "answers user_does_not_exist, as Google login does" do
          expect(code_for(result)).to eq(["user_does_not_exist"])
        end
      end
    end

    it "refuses a revoked-only user and a legacy user without membership" do
      revoked = create(:user, email: "jane@getlago.com")
      create(:membership, :revoked, user: revoked)
      expect(code_for(result)).to eq(["user_does_not_exist"])

      revoked.update!(email: "old@getlago.com")
      create(:user, email: "jane@getlago.com")
      expect(code_for(described_class.call(code: "code", state: issued.state, state_secret: issued.secret))).to eq(["user_does_not_exist"])
    end
  end

  describe "pending email signups for the address" do
    let(:signup_secret) { PendingSignup.generate_signup_secret }
    let(:token) { PendingSignupToken.generate }
    let!(:pending_signup) { create(:pending_signup, email: "jane@getlago.com", signup_secret:) }

    before { create(:pending_signup_token, pending_signup:, token:) }

    def expect_pending_signup_unusable
      expect(pending_signup.reload).to have_attributes(verified_at: nil, user_id: nil, password_digest: nil)
      expect(Signups::StatusService.call(signup_secret:).status).to eq(:pending)
      expect(Signups::ExchangeSecretService.call(signup_secret:).error.code).to eq("email_not_verified")
      expect { Signups::ConfirmService.call(token:, signup_secret:) }.not_to change(User, :count)
      # A user now exists for the address, which comes first in the link's states.
      expect(Signups::ConfirmService.call(token:, signup_secret:).error.code).to eq("email_already_verified")
    end

    it "never verifies or links them, so their secret never opens the Google user's session" do
      result

      expect_pending_signup_unusable
    end

    it "leaves them unchanged when the Google signup is refused" do
      allow(Google::Auth::IDTokens).to receive(:verify_oidc).and_return("email" => "jane@getlago.com", "email_verified" => false)

      expect { result }.not_to change { pending_signup.reload.attributes }
    end
  end

  context "when another request holds the address", transaction: false do
    before { stub_const("BaseLockService::ACQUIRE_LOCK_TIMEOUT", 0.seconds) }

    it "answers lock_acquisition_failed and creates nothing" do
      with_email_lock("jane@getlago.com") do
        expect(result.error.code).to eq("lock_acquisition_failed")
      end

      expect(User.count).to eq(0)
    end
  end
end
