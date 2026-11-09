# frozen_string_literal: true

require "rails_helper"

RSpec.describe Auth::GoogleLoginRules do
  describe ".email_verified?" do
    it "is true only for a verified email" do
      expect(described_class.email_verified?("email_verified" => true)).to be(true)
      expect(described_class.email_verified?("email_verified" => "true")).to be(true)
      expect(described_class.email_verified?("email_verified" => false)).to be(false)
      expect(described_class.email_verified?({})).to be(false)
    end
  end

  describe ".refusal" do
    subject(:refusal) { described_class.refusal(user, claims) }

    let(:claims) { {"email" => "jane@getlago.com", "email_verified" => true} }
    let(:organization) { create(:organization) }
    let(:user) { create(:user, email: "jane@getlago.com") }

    context "with an active member of an organization that allows Google" do
      before { create(:membership, user:, organization:) }

      it { is_expected.to be_nil }
    end

    context "with an organization that does not allow Google" do
      let(:organization) { create(:organization, authentication_methods: %w[email_password]) }

      before { create(:membership, user:, organization:) }

      it { is_expected.to eq(error_code: "login_method_not_authorized", field: "google_oauth") }
    end

    context "without a user" do
      let(:user) { nil }

      it { is_expected.to eq(error_code: "user_does_not_exist") }
    end

    context "with a user whose membership was revoked" do
      before { create(:membership, :revoked, user:, organization:) }

      it { is_expected.to eq(error_code: "user_does_not_exist") }
    end

    context "with a self-serve user who has no organization yet" do
      include_context "with self-serve enabled"

      let(:user) { create(:user, :self_serve, email: "jane@getlago.com") }

      it { is_expected.to be_nil }

      context "when Google did not verify the email" do
        let(:claims) { {"email" => "jane@getlago.com", "email_verified" => false} }

        it { is_expected.to eq(error_code: "user_does_not_exist") }
      end
    end
  end
end
