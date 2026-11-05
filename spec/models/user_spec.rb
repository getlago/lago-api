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

  describe "#needs_organization?" do
    let(:user) { create(:user, :self_serve) }

    context "when self-serve is on" do
      include_context "with self-serve enabled"

      it "is true only for a self-serve user, not a CS admin, who never had a membership" do
        expect(user.needs_organization?).to be(true)
        expect(create(:user).needs_organization?).to be(false)
        expect(create(:user, :self_serve, cs_admin: true).needs_organization?).to be(false)
      end

      it "is false once the user had a membership, even revoked" do
        create(:membership, :revoked, user:)

        expect(user.reload.needs_organization?).to be(false)
      end

      it "is false with an active membership" do
        create(:membership, user:)

        expect(user.reload.needs_organization?).to be(false)
      end
    end

    it "is false when self-serve is off" do
      expect(user.needs_organization?).to be(false)
    end
  end

  describe ".lookup_by_email" do
    it "prefers the exact match, then the oldest case-insensitive one" do
      older = create(:user, email: "Jane@GetLago.com", created_at: 2.days.ago)
      exact = create(:user, email: "jane@getlago.com", created_at: 1.day.ago)

      expect(described_class.lookup_by_email("jane@getlago.com")).to eq(exact)
      expect(described_class.lookup_by_email("JANE@getlago.com")).to eq(older)
    end

    it "matches spelling variants and returns nil for an unknown email" do
      user = create(:user, email: "jane-doe@getlago.com")

      expect(described_class.lookup_by_email(" JANE\u2013doe@get\u200Blago.com ")).to eq(user)
      expect(described_class.lookup_by_email("nobody@getlago.com")).to be_nil
    end

    it "matches either Unicode spelling, and a row stored decomposed by its own" do
      composed = create(:user, email: "jo\u00E3o@getlago.com")
      decomposed = create(:user, email: "Mari\u0301a@getlago.com")

      expect(described_class.lookup_by_email("Joa\u0303o@getlago.com")).to eq(composed)
      expect(described_class.lookup_by_email("mari\u0301a@getlago.com")).to eq(decomposed)
    end

    it "finds the exact spelling even where PostgreSQL lowercases it otherwise than Ruby" do
      user = create(:user, email: "\u0130lker@getlago.com")

      expect(described_class.lookup_by_email("\u0130lker@getlago.com")).to eq(user)
    end

    it "prefers the typed spelling ignoring case to an older row in another Unicode spelling" do
      create(:user, email: "jo\u00E3o@getlago.com", created_at: 2.days.ago)
      typed = create(:user, email: "Joa\u0303o@getlago.com", created_at: 1.day.ago)

      expect(described_class.lookup_by_email("joa\u0303o@getlago.com")).to eq(typed)
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

    context "when built from the password digest of a confirmed signup" do
      subject(:user) { described_class.new(email: "jane@getlago.com", password_digest: PendingSignup.digest_password("Lago-Passw0rd")) }

      it "is valid without a password and accepts the Step 1 password" do
        expect(user).to be_valid
        expect(user.authenticate("Lago-Passw0rd")).to eq(user)
      end
    end

    it "is not valid without a password or a digest" do
      expect(described_class.new(email: "jane@getlago.com")).not_to be_valid
    end

    it "still needs a password when an existing user's digest is cleared" do
      user = create(:user)
      user.password_digest = nil

      expect(user).not_to be_valid
    end
  end
end
