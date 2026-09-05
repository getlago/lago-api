# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlanRateCard do
  subject(:plan_rate_card) { build(:plan_rate_card) }

  it_behaves_like "paper_trail traceable"

  describe "associations" do
    it do
      expect(plan_rate_card).to belong_to(:organization)
      expect(plan_rate_card).to belong_to(:plan).optional
      expect(plan_rate_card).to belong_to(:catalog_plan).optional
      expect(plan_rate_card).to belong_to(:rate_card)
      expect(plan_rate_card).to have_many(:rate_phases).order(:position)
      expect(plan_rate_card).to have_one(:product).through(:rate_card)
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

    describe "units" do
      it "rejects a negative value and accepts zero or nil" do
        entry = build(:plan_rate_card, units: -1)
        expect(entry).not_to be_valid
        expect(entry.errors.where(:units, :greater_than_or_equal_to)).to be_present

        expect(build(:plan_rate_card, units: 0)).to be_valid
        expect(build(:plan_rate_card, units: nil)).to be_valid
      end
    end

    describe "exactly one plan" do
      let(:catalog_plan) { create(:catalog_plan) }

      it "accepts a catalog plan instead of a plan" do
        expect(build(:plan_rate_card, plan: nil, catalog_plan:, organization: catalog_plan.organization)).to be_valid
      end

      it "rejects both a plan and a catalog plan" do
        card = build(:plan_rate_card, catalog_plan:)

        expect(card).not_to be_valid
        expect(card.errors.where(:base, :exactly_one_plan_required)).to be_present
      end

      it "rejects neither" do
        card = build(:plan_rate_card, plan: nil)

        expect(card).not_to be_valid
        expect(card.errors.where(:base, :exactly_one_plan_required)).to be_present
      end

      it "scopes rate card uniqueness to the catalog plan" do
        existing = create(:plan_rate_card, plan: nil, catalog_plan:, organization: catalog_plan.organization)
        duplicate = build(:plan_rate_card, plan: nil, catalog_plan:, organization: catalog_plan.organization, rate_card: existing.rate_card)
        duplicate.valid?

        expect(duplicate.errors.where(:rate_card_id, :taken)).to be_present
      end
    end

    describe "database parent guard" do
      it "rejects a row with neither plan even past model validation" do
        card = build(:plan_rate_card, plan: nil)

        expect { card.save(validate: false) }.to raise_error(ActiveRecord::StatementInvalid)
      end

      it "rejects a row with both plans even past model validation" do
        card = build(:plan_rate_card, catalog_plan: create(:catalog_plan))

        expect { card.save(validate: false) }.to raise_error(ActiveRecord::StatementInvalid)
      end
    end
  end

  describe "#edit_error_code" do
    it "is nil while the plan has no subscriptions" do
      expect(create(:plan_rate_card).edit_error_code).to be_nil
    end

    it "is plan_locked once the plan has subscriptions" do
      card = create(:plan_rate_card)
      create(:subscription, plan: card.plan)

      expect(card.edit_error_code).to eq("plan_locked")
    end
  end
end
