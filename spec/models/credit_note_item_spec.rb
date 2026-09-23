# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreditNoteItem do
  subject(:credit_note_item) { create(:credit_note_item) }

  it { is_expected.to belong_to(:credit_note) }
  it { is_expected.to belong_to(:fee) }
  it { is_expected.to belong_to(:organization) }

  describe "#applied_taxes" do
    subject(:applied_taxes) { credit_note_item.applied_taxes }

    let(:credit_note_item) { create(:credit_note_item) }
    let(:tax_code) { "provider_tax" }
    let(:matching_rate) { 8.875001 }
    let(:other_rate) { 8.875002 }
    let(:matching_tax) do
      create(:credit_note_applied_tax, credit_note: credit_note_item.credit_note, tax: nil, tax_code:, tax_rate: matching_rate)
    end
    let(:other_tax) do
      create(:credit_note_applied_tax, credit_note: credit_note_item.credit_note, tax: nil, tax_code:, tax_rate: other_rate)
    end
    let(:fee_applied_tax) do
      create(:fee_applied_tax, fee: credit_note_item.fee, tax: nil, tax_code:, tax_rate: matching_tax.tax_rate)
    end

    before do
      matching_tax
      other_tax
      fee_applied_tax
    end

    it "returns the exact credit note tax when rates differ beyond five decimals" do
      expect(applied_taxes).to be_a(ActiveRecord::Relation)
      expect(credit_note_item.credit_note.applied_taxes.count).to eq(2)
      expect(applied_taxes.pluck(:id)).to eq([matching_tax.id])
    end

    context "when the fee rate differs from the only credit note tax carrying that code" do
      let(:other_tax) { nil }
      let(:fee_applied_tax) do
        create(:fee_applied_tax, fee: credit_note_item.fee, tax: nil, tax_code:, tax_rate: 20.0)
      end

      it "returns that credit note tax, as the tax calculation resolved it" do
        expect(applied_taxes.pluck(:id)).to eq([matching_tax.id])
      end
    end

    context "when the fee rate matches none of several credit note taxes sharing that code" do
      let(:fee_applied_tax) do
        create(:fee_applied_tax, fee: credit_note_item.fee, tax: nil, tax_code:, tax_rate: 20.0)
      end

      it "returns nothing rather than picking one" do
        expect(applied_taxes).to be_empty
      end
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
