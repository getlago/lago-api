# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invites::AuthenticateUserService do
  subject(:authentication_result) { described_class.call(user:, password:) }

  let(:user) { create(:user, password: "CurrentPassword!") }
  let(:password) { "CurrentPassword!" }
  let(:authentication_methods) { %w[email_password google_oauth] }
  let(:organization) { create(:organization, authentication_methods:) }
  let(:membership_status) { :active }

  before { create(:membership, user:, organization:, status: membership_status) }

  it "authenticates without changing the existing password" do
    expect { authentication_result }.not_to change { user.reload.password_digest }
    expect(authentication_result).to be_success
  end

  context "with an incorrect password" do
    let(:password) { "WrongPassword!" }

    it "returns a validation failure without changing the password" do
      expect { authentication_result }.not_to change { user.reload.password_digest }
      expect(authentication_result).not_to be_success
      expect(authentication_result.error.messages[:base]).to eq(["incorrect_login_or_password"])
    end

    context "without a password" do
      let(:password) { nil }

      it "returns a validation failure" do
        expect(authentication_result.error.messages[:base]).to eq(["incorrect_login_or_password"])
      end
    end

    context "with a null byte in the password" do
      let(:password) { "CurrentPassword!\u0000" }

      it "returns a validation failure" do
        expect(authentication_result.error.messages[:base]).to eq(["incorrect_login_or_password"])
      end
    end
  end

  context "when the user's organization requires SSO" do
    let(:authentication_methods) { %w[google_oauth] }

    it "rejects password authentication" do
      expect(authentication_result).not_to be_success
      expect(authentication_result.error.messages[:email_password]).to eq(["login_method_not_authorized"])
    end

    context "when another organization allows password authentication" do
      before { create(:membership, user:) }

      it "allows password authentication" do
        expect(authentication_result).to be_success
      end
    end

    context "when the membership is revoked" do
      let(:membership_status) { :revoked }

      it "authenticates without changing the existing password" do
        expect { authentication_result }.not_to change { user.reload.password_digest }
        expect(authentication_result).to be_success
      end

      context "with an incorrect password" do
        let(:password) { "WrongPassword!" }

        it "returns a validation failure" do
          expect(authentication_result.error.messages[:base]).to eq(["incorrect_login_or_password"])
        end
      end
    end
  end
end
