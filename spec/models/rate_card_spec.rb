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
      expect(rate_card).to have_many(:rates).class_name("RateCardRate")
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

    describe "code uniqueness per organization" do
      it "rejects a duplicate code within the same organization, even on a different product item" do
        existing = create(:rate_card)
        duplicate = build(:rate_card, organization: existing.organization, code: existing.code)
        duplicate.valid?
        expect(duplicate.errors.where(:code, :taken)).to be_present
      end

      it "allows the same code in a different organization" do
        existing = create(:rate_card)
        other = build(:rate_card, code: existing.code)
        other.valid?
        expect(other.errors.where(:code, :taken)).not_to be_present
      end
    end
  end

  describe "#attached_to_plan_or_subscription?" do
    let(:rate_card) { create(:rate_card) }

    it "is false when no plan or subscription references the card" do
      expect(rate_card.attached_to_plan_or_subscription?).to be(false)
    end

    it "is true when a plan references the card" do
      create(:plan_rate_card, organization: rate_card.organization, rate_card:)

      expect(rate_card.attached_to_plan_or_subscription?).to be(true)
    end

    it "is true when a subscription references the card" do
      create(:subscription_rate_card, organization: rate_card.organization, rate_card:)

      expect(rate_card.attached_to_plan_or_subscription?).to be(true)
    end
  end
end
