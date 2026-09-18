# frozen_string_literal: true

require "rails_helper"

RSpec.describe User do
  subject { described_class.new(email: "gavin@hooli.com", password: "f**k_piedpiper") }

  it_behaves_like "paper_trail traceable"

  describe "associations" do
    it do
      expect(subject).to have_many(:password_resets)
      expect(subject).to have_many(:user_devices)
      expect(subject).to have_many(:memberships)
      expect(subject).to have_many(:organizations).through(:memberships).class_name("Organization")
      expect(subject).to have_many(:active_memberships).class_name("Membership")
      expect(subject).to have_many(:active_organizations).through(:active_memberships).source(:organization)
      expect(subject).to have_many(:quote_owners).dependent(:destroy)
      expect(subject).to have_many(:quotes).through(:quote_owners)
    end
  end

  describe "normalizations" do
    it "sanitizes email on assignment" do
      user = described_class.new(email: " hello@some\u200Bthing\u2013other.com ", password: "password")
      expect(user.email).to eq("hello@something-other.com")
    end
  end

  describe "#login_method_allowed?" do
    let(:user) { create(:user) }
    let(:organization) { create(:organization) }

    context "when an active organization of the user allows the login method" do
      before { create(:membership, organization:, user:) }

      it "returns true" do
        expect(user.login_method_allowed?(Organizations::AuthenticationMethods::EMAIL_PASSWORD)).to be true
      end
    end

    context "when no active organization of the user allows the login method" do
      before do
        create(:membership, organization:, user:)
        organization.disable_email_password_authentication!
      end

      it "returns false" do
        expect(user.login_method_allowed?(Organizations::AuthenticationMethods::EMAIL_PASSWORD)).to be false
      end
    end

    context "when the membership of the user is revoked" do
      before { create(:membership, :revoked, organization:, user:) }

      it "returns false" do
        expect(user.login_method_allowed?(Organizations::AuthenticationMethods::EMAIL_PASSWORD)).to be false
      end
    end
  end

  describe "Validations" do
    it "is valid with valid attributes" do
      expect(subject).to be_valid
    end

    it "is not valid with no email" do
      subject.email = nil
      expect(subject).not_to be_valid
    end

    it "is not valid with no password" do
      subject.password = nil
      expect(subject).not_to be_valid
    end
  end
end
