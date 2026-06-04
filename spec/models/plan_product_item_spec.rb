# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlanProductItem do
  subject(:plan_product_item) { build(:plan_product_item) }

  it_behaves_like "paper_trail traceable"

  describe "associations" do
    it do
      expect(plan_product_item).to belong_to(:organization)
      expect(plan_product_item).to belong_to(:plan)
      expect(plan_product_item).to belong_to(:rate_card)
      expect(plan_product_item).to have_one(:product_item).through(:rate_card)
    end
  end

  describe "validations" do
    describe "uniqueness of (plan, rate_card)" do
      it "rejects a duplicate plan / rate_card pair" do
        existing = create(:plan_product_item)
        duplicate = build(
          :plan_product_item,
          organization: existing.organization,
          plan: existing.plan,
          rate_card: existing.rate_card
        )
        duplicate.valid?
        expect(duplicate.errors.where(:rate_card_id, :taken)).to be_present
      end

      it "allows a different rate_card on the same plan" do
        existing = create(:plan_product_item)
        other_card = create(:rate_card, organization: existing.organization)
        sibling = build(
          :plan_product_item,
          organization: existing.organization,
          plan: existing.plan,
          rate_card: other_card
        )
        expect(sibling).to be_valid
      end
    end
  end
end
