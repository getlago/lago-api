# frozen_string_literal: true

require "rails_helper"

RSpec.describe Signups::ExchangeSecretService do
  subject(:result) { described_class.call(signup_secret:) }

  let(:signup_secret) { PendingSignup.generate_signup_secret }
  let(:token) { PendingSignupToken.generate }
  let(:pending_signup) { create(:pending_signup, signup_secret:) }

  before do
    freeze_time
    create(:pending_signup_token, pending_signup:, token:)
  end

  context "when the link was confirmed less than an hour ago" do
    before { Signups::ConfirmService.call!(token:, signup_secret:) }

    it "opens a session for the user the confirm created, once" do
      expect(result.user).to eq(pending_signup.reload.user)
      expect(Utils::AuthToken.decode(token: result.token)["sub"]).to eq(result.user.id)
      expect(pending_signup.reload.signup_secret_exchanged_at).to eq(Time.current)

      expect(described_class.call(signup_secret:).error.code).to eq("signup_secret_expired")
    end

    context "when the session cannot be opened" do
      before do
        calls = 0
        allow(UserDevices::RegisterService).to receive(:call!).and_wrap_original do |original, **kwargs|
          calls += 1
          raise ActiveRecord::ConnectionFailed, "connection lost" if calls == 1

          original.call(**kwargs)
        end
      end

      it "keeps the secret exchangeable, so a retry opens the session" do
        expect { result }.to raise_error(ActiveRecord::ConnectionFailed)
        expect(pending_signup.reload.signup_secret_exchanged_at).to be_nil

        expect(described_class.call(signup_secret:)).to be_success
      end
    end

    it "refuses after an hour" do
      travel(1.hour + 1.second)

      expect(result.error.code).to eq("signup_secret_expired")
    end
  end

  it "refuses before the confirmation" do
    expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
    expect(result.error.code).to eq("email_not_verified")
  end

  it "answers not_found for an unknown secret" do
    error = described_class.call(signup_secret: PendingSignup.generate_signup_secret).error

    expect(error).to be_a(BaseService::NotFoundFailure)
    expect(error.resource).to eq("signup_secret")
  end

  context "when an attempt was marked verified without a consumed link" do
    before { pending_signup.update!(verified_at: Time.current, user: create(:user), password_digest: nil) }

    it "refuses, since only the confirm makes a secret exchangeable" do
      expect(result.error.code).to eq("signup_secret_expired")
    end
  end
end
