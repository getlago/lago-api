# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlanProductItem do
  subject(:plan_product_item) { build(:plan_product_item) }

  it_behaves_like "paper_trail traceable"

  describe "associations" do
    it do
      expect(plan_product_item).to belong_to(:organization)
      expect(plan_product_item).to belong_to(:plan)
      expect(plan_product_item).to belong_to(:product_item)
      expect(plan_product_item).to belong_to(:rate_card)
    end
  end

  describe "validations" do
    describe "uniqueness of (plan, product_item, rate_card)" do
      it "rejects a duplicate plan / product_item / rate_card triple" do
        existing = create(:plan_product_item)
        duplicate = build(
          :plan_product_item,
          organization: existing.organization,
          plan: existing.plan,
          product_item: existing.product_item,
          rate_card: existing.rate_card
        )
        duplicate.valid?
        expect(duplicate.errors.where(:rate_card_id, :taken)).to be_present
      end

      it "allows the same product_item on a plan with a different rate_card" do
        existing = create(:plan_product_item)
        other_card = create(:rate_card, organization: existing.organization, product_item: existing.product_item)
        sibling = build(
          :plan_product_item,
          organization: existing.organization,
          plan: existing.plan,
          product_item: existing.product_item,
          rate_card: other_card
        )
        expect(sibling).to be_valid
      end
    end
  end
end
