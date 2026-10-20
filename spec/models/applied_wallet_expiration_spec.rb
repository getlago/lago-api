# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppliedWalletExpiration do
  subject { build(:applied_wallet_expiration) }

  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:invoice)
      expect(subject).to belong_to(:wallet)
    end
  end

  describe "validations" do
    subject { create(:applied_wallet_expiration) }

    it do
      expect(subject).to validate_uniqueness_of(:invoice_id).ignoring_case_sensitivity
    end
  end
end
