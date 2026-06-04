# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateCard do
  subject(:rate_card) { build(:rate_card) }

  it_behaves_like "paper_trail traceable"

  describe "enums" do
    it do
      expect(rate_card).to define_enum_for(:billing_timing)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(arrears: "arrears", advance: "advance")

      expect(rate_card).to define_enum_for(:proration)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(full: "full", none: "none")
        .with_prefix

      expect(rate_card).to define_enum_for(:regroup_paid_fees)
        .backed_by_column_of_type(:enum)
        .validating(allowing_nil: true)
        .with_values(invoice: "invoice")
    end
  end

  describe "associations" do
    it do
      expect(rate_card).to belong_to(:organization)
      expect(rate_card).to belong_to(:product_item)
      expect(rate_card).to belong_to(:product_item_filter).optional
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:code) }

    describe "currency inclusion" do
      it "is valid with an accepted currency" do
        expect(build(:rate_card, currency: "USD")).to be_valid
      end

      it "is invalid with an unknown currency" do
        rate_card = build(:rate_card, currency: "ABC")
        rate_card.valid?
        expect(rate_card.errors.where(:currency, :inclusion)).to be_present
      end
    end

    describe "code uniqueness per product item and filter" do
      it "rejects a duplicate code on the same product item and filter scope" do
        existing = create(:rate_card)
        duplicate = build(
          :rate_card,
          organization: existing.organization,
          product_item: existing.product_item,
          code: existing.code
        )
        duplicate.valid?
        expect(duplicate.errors.where(:code, :taken)).to be_present
      end

      it "allows the same code on a different product item" do
        existing = create(:rate_card)
        other = build(:rate_card, organization: existing.organization, code: existing.code)
        other.valid?
        expect(other.errors.where(:code, :taken)).not_to be_present
      end
    end
  end
end
