# frozen_string_literal: true

require "rails_helper"

RSpec.describe PasswordResets::CreateJob do
  let(:user) { create(:user) }

  before { allow(PasswordResets::CreateService).to receive(:call!) }

  it "creates the password reset for the matching user" do
    described_class.perform_now(user.email)

    expect(PasswordResets::CreateService).to have_received(:call!).with(user:)
  end

  context "when the stored email casing differs from the requested email" do
    let(:user) { create(:user, email: "Jane@acme.com") }

    before { user }

    it "creates the password reset for the existing user" do
      described_class.perform_now("jane@acme.com")

      expect(PasswordResets::CreateService).to have_received(:call!).with(user:)
    end
  end

  it "passes no user for an unknown email" do
    described_class.perform_now("nobody@example.com")

    expect(PasswordResets::CreateService).to have_received(:call!).with(user: nil)
  end
end
