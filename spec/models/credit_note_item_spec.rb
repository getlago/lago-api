# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreditNoteItem do
  subject(:credit_note_item) { create(:credit_note_item) }

  it { is_expected.to belong_to(:credit_note) }
  it { is_expected.to belong_to(:fee) }
  it { is_expected.to belong_to(:organization) }

  describe "#applied_taxes" do
    it "matches complete tax identities without mixing rates and types" do
      credit_note = credit_note_item.credit_note
      matching_taxes = [[20, "sales"], [10, "vat"]].map do |rate, type|
        attributes = {tax: nil, tax_code: "tax", tax_rate: rate, tax_description: type}
        create(:fee_applied_tax, fee: credit_note_item.fee, **attributes)
        create(:credit_note_applied_tax, credit_note:, **attributes)
      end
      create(:credit_note_applied_tax, credit_note:, tax: nil, tax_code: "tax", tax_rate: 10, tax_description: "sales")
      create(:credit_note_applied_tax, credit_note:, tax: nil, tax_code: "tax", tax_rate: 20, tax_description: "vat")

      expect(credit_note_item.applied_taxes).to match_array(matching_taxes)
    end

    it "returns no taxes when the fee has none" do
      create(:credit_note_applied_tax, credit_note: credit_note_item.credit_note)

      expect(credit_note_item.applied_taxes).to be_empty
    end
  end

  describe "#sub_total_excluding_taxes_amount_cents" do
    let(:credit_note_item) { build(:credit_note_item, amount_cents: 100, fee: fee) }
    let(:fee) { build(:fee, amount_cents: 1000, precise_amount_cents: 1000, precise_coupons_amount_cents: 0) }

    context "when there are no coupons applied" do
      it "returns item amount with coupons applied" do
        expect(credit_note_item.sub_total_excluding_taxes_amount_cents).to eq(100)
      end
    end

    context "when there are coupons applied" do
      let(:fee) { build(:fee, amount_cents: 1000, precise_amount_cents: 1000, precise_coupons_amount_cents: 20) }

      it "returns item amount with coupons applied" do
        expect(credit_note_item.sub_total_excluding_taxes_amount_cents).to eq(98)
      end
    end
  end
end
