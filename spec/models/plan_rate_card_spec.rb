# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlanRateCard do
  subject(:plan_rate_card) { build(:plan_rate_card) }

  it_behaves_like "paper_trail traceable"

  describe "associations" do
    it do
      expect(plan_rate_card).to belong_to(:organization)
      expect(plan_rate_card).to belong_to(:plan)
      expect(plan_rate_card).to belong_to(:rate_card)
      expect(plan_rate_card).to have_one(:product_item).through(:rate_card)
    end
  end

  describe "validations" do
    describe "uniqueness of (plan, rate_card)" do
      it "rejects a duplicate plan / rate_card pair" do
        existing = create(:plan_rate_card)
        duplicate = build(
          :plan_rate_card,
          organization: existing.organization,
          plan: existing.plan,
          rate_card: existing.rate_card
        )
        duplicate.valid?
        expect(duplicate.errors.where(:rate_card_id, :taken)).to be_present
      end

      it "allows a different rate_card on the same plan" do
        existing = create(:plan_rate_card)
        other_card = create(:rate_card, organization: existing.organization)
        sibling = build(
          :plan_rate_card,
          organization: existing.organization,
          plan: existing.plan,
          rate_card: other_card
        )
        expect(sibling).to be_valid
      end
    end
  end

  it_behaves_like "a rate phase parent" do
    let(:item) { create(:plan_rate_card) }
    let(:create_rate_phase) do
      ->(attributes) { create(:rate_phase, plan_rate_card: item, **attributes) }
    end
  end
end
