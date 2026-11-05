# frozen_string_literal: true

require "rails_helper"

RSpec.describe Signups::ConfirmService do
  subject(:result) { described_class.call(token:, signup_secret:, password:) }

  let(:attempt_secret) { PendingSignup.generate_signup_secret }
  let(:step_one_password) { "Signup-Passw0rd" }
  let(:pending_signup) { create(:pending_signup, email: "Jane@GetLago.com", signup_secret: attempt_secret, password: step_one_password) }
  let(:token) { PendingSignupToken.generate }
  let!(:token_record) { create(:pending_signup_token, pending_signup:, token:) }
  let(:signup_secret) { attempt_secret }
  let(:password) { nil }

  before do
    freeze_time
    allow(BCrypt::Password).to receive(:new).and_call_original
  end

  shared_examples "a confirmed signup" do
    it "creates the user from the Step 1 digest, with no organization" do
      expect { result }.to change(User, :count).by(1).and not_change(Organization, :count).and not_change(Membership, :count)

      expect(result.user).to have_attributes(email: "Jane@GetLago.com", cs_admin: false, self_serve_verified_at: Time.current)
      expect(result.user.authenticate(step_one_password)).to eq(result.user)
    end

    it "consumes the link, marks the attempt verified and drops its password digest" do
      result

      expect(token_record.reload).to have_attributes(status: "consumed", consumed_at: Time.current)
      expect(pending_signup.reload).to have_attributes(verified_at: Time.current, user: result.user, password_digest: nil)
    end

    it "opens a password session for the new user" do
      decoded = Utils::AuthToken.decode(token: result.token)

      expect(decoded["sub"]).to eq(result.user.id)
      expect(decoded["login_method"]).to eq(Organizations::AuthenticationMethods::EMAIL_PASSWORD)
    end

    it "closes the other open attempts of the address, not those of a +tag" do
      other = create(:pending_signup, email: "jane@getlago.com")
      other_token = create(:pending_signup_token, pending_signup: other)
      tagged = create(:pending_signup, email: "jane+x@getlago.com")

      result

      expect(other.reload).to have_attributes(password_digest: nil, closed_at: Time.current)
      expect(other_token.reload).to be_replaced
      expect(tagged.reload.closed_at).to be_nil
    end
  end

  context "with the signup secret of the attempt" do
    it_behaves_like "a confirmed signup"

    it "runs no bcrypt" do
      result

      expect(BCrypt::Password).not_to have_received(:new)
    end
  end

  context "with the Step 1 password, on another device" do
    let(:signup_secret) { nil }
    let(:password) { step_one_password }

    it_behaves_like "a confirmed signup"
  end

  context "with a wrong password" do
    let(:signup_secret) { nil }
    let(:password) { "Wrong-Passw0rd" }

    it "creates nothing and counts the try" do
      expect { result }.not_to change(User, :count)

      expect(result.error.messages).to eq(password: ["incorrect_password"])
      expect(token_record.reload.failed_password_attempts).to eq(1)
    end
  end

  it "locks the link after 5 password tries" do
    5.times { described_class.call(token:, password: "Wrong-Passw0rd") }

    expect(token_record.reload.failed_password_attempts).to eq(5)
    expect(described_class.call(token:, password: step_one_password).error.code).to eq("signup_token_locked")
  end

  it "accepts the right password on the fifth try" do
    4.times { described_class.call(token:, password: "Wrong-Passw0rd") }

    expect { described_class.call!(token:, password: step_one_password) }.to change(User, :count).by(1)
    expect(token_record.reload).to have_attributes(status: "consumed", failed_password_attempts: 5)
  end

  context "with a locked link" do
    let!(:token_record) { create(:pending_signup_token, :locked, pending_signup:, token:) }
    let(:signup_secret) { nil }
    let(:password) { step_one_password }

    it "refuses even the right password, without running bcrypt" do
      expect(result.error.code).to eq("signup_token_locked")
      expect(BCrypt::Password).not_to have_received(:new)
      expect(User.count).to eq(0)
    end
  end

  context "with a link locked by password tries, and the attempt's secret" do
    let!(:token_record) { create(:pending_signup_token, :locked, pending_signup:, token:) }

    it_behaves_like "a confirmed signup"
  end

  context "with a password over 72 bytes" do
    let(:signup_secret) { nil }
    let(:password) { "Aa1-#{"é" * 40}" }

    it "refuses without counting a try or running bcrypt" do
      expect(result.error.messages).to eq(password: ["incorrect_password"])
      expect(token_record.reload.failed_password_attempts).to eq(0)
      expect(BCrypt::Password).not_to have_received(:new)
    end
  end

  context "with neither the secret nor a password" do
    let(:signup_secret) { nil }

    it "asks for the password" do
      expect(result.error.messages).to eq(password: ["password_required"])
    end
  end

  context "with the secret of another attempt of the same address" do
    let(:signup_secret) { PendingSignup.generate_signup_secret }

    before { create(:pending_signup, email: "jane@getlago.com", signup_secret:) }

    it "asks for this attempt's password" do
      expect(result.error.messages).to eq(password: ["password_required"])
      expect(User.count).to eq(0)
    end
  end

  context "with the password of another attempt of the same address" do
    let(:signup_secret) { nil }
    let(:password) { "Other-Passw0rd" }

    before { create(:pending_signup, email: "jane@getlago.com", password: "Other-Passw0rd") }

    it "refuses it" do
      expect(result.error.messages).to eq(password: ["incorrect_password"])
    end
  end

  it "refuses an expired, replaced or unknown link" do
    # The link was created before freeze_time, with sub-seconds.
    travel(24.hours + 1.second)
    expect(described_class.call(token:, signup_secret:).error.code).to eq("signup_token_expired")

    travel_back
    token_record.update!(status: "replaced")
    expect(described_class.call(token:, signup_secret:).error.code).to eq("signup_token_replaced")

    unknown = described_class.call(token: PendingSignupToken.generate, signup_secret:).error
    expect([unknown.class, unknown.resource]).to eq([BaseService::NotFoundFailure, "signup_token"])
    expect(described_class.call(token: "broken", signup_secret:).error.resource).to eq("signup_token")
  end

  it "refuses a link of a closed attempt, whose password digest is gone" do
    pending_signup.update!(closed_at: Time.current, password_digest: nil)

    expect { result }.not_to change(User, :count)
    expect(result.error.code).to eq("signup_token_expired")
  end

  it "refuses a second confirmation" do
    described_class.call!(token:, signup_secret:)

    expect { result }.not_to change(User, :count)
    expect(result.error.code).to eq("email_already_verified")
  end

  context "when a user was created for the address meanwhile, whatever its case" do
    before { create(:user, email: "jane@getlago.com") }

    it "refuses and keeps a single user" do
      expect { result }.not_to change(User, :count)
      expect(result.error.code).to eq("email_already_verified")
    end
  end

  context "when another request holds the address", transaction: false do
    before { stub_const("BaseLockService::ACQUIRE_LOCK_TIMEOUT", 0.seconds) }

    it "checks a wrong password before taking the lock" do
      with_email_lock("jane@getlago.com") do
        expect(described_class.call(token:, password: "Wrong-Passw0rd").error.messages).to eq(password: ["incorrect_password"])
      end
    end

    it "answers lock_acquisition_failed for a valid proof and creates nothing" do
      with_email_lock("jane@getlago.com") do
        expect(result.error.code).to eq("lock_acquisition_failed")
      end

      expect(User.count).to eq(0)
    end
  end
end
