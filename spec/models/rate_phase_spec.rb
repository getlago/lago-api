# frozen_string_literal: true

require "rails_helper"

RSpec.describe RatePhase do
  subject(:rate_phase) { build(:rate_phase) }

  it_behaves_like "paper_trail traceable"

  describe "associations" do
    it do
      expect(rate_phase).to belong_to(:organization)
      expect(rate_phase).to belong_to(:plan_product_item).optional
      expect(rate_phase).to belong_to(:subscription_product_item).optional
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:position) }
    it { is_expected.to validate_numericality_of(:position).is_greater_than(0) }

    describe "exactly one parent" do
      it "is valid with only a plan_product_item" do
        expect(build(:rate_phase)).to be_valid
      end

      it "is valid with only a subscription_product_item" do
        expect(build(:rate_phase, :subscription_level)).to be_valid
      end

      it "is invalid with neither parent" do
        phase = build(:rate_phase, plan_product_item: nil, subscription_product_item: nil)
        phase.valid?
        expect(phase.errors.added?(:base, :exactly_one_parent_required)).to be(true)
      end

      it "is invalid with both parents" do
        phase = build(
          :rate_phase,
          plan_product_item: create(:plan_product_item),
          subscription_product_item: create(:subscription_product_item)
        )
        phase.valid?
        expect(phase.errors.added?(:base, :exactly_one_parent_required)).to be(true)
      end
    end
  end
end
