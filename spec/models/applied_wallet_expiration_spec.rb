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

  describe ".with_unsettled_invoice" do
    let(:wallet) { create(:wallet) }

    def applied_to_invoice(**invoice_attributes)
      invoice = create(:invoice, organization: wallet.organization, customer: wallet.customer, **invoice_attributes)
      create(:applied_wallet_expiration, wallet:, invoice:)
    end

    it "returns the expirations whose invoice can still apply the wallet credits" do
      awaiting_taxes = applied_to_invoice(status: :pending, tax_status: :pending)
      gated_awaiting_taxes = applied_to_invoice(status: :open, tax_status: :pending)
      failed = applied_to_invoice(status: :failed)
      generated_awaiting_taxes = applied_to_invoice(status: :generating, tax_status: :pending)
      applied_to_invoice(status: :finalized)
      applied_to_invoice(status: :voided)
      applied_to_invoice(status: :generating)
      applied_to_invoice(status: :open, tax_status: :succeeded)

      expect(described_class.with_unsettled_invoice)
        .to contain_exactly(awaiting_taxes, gated_awaiting_taxes, failed, generated_awaiting_taxes)
    end
  end
end
