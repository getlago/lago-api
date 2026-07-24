# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlanProduct do
  subject(:plan_product) { build(:plan_product) }

  it_behaves_like "paper_trail traceable"

  describe "associations" do
    it do
      expect(plan_product).to belong_to(:organization)
      expect(plan_product).to belong_to(:plan)
      expect(plan_product).to belong_to(:product)
    end
  end

  describe "validations" do
    describe "product uniqueness per plan" do
      it "rejects assigning the same product to a plan twice" do
        existing = create(:plan_product)
        duplicate = build(:plan_product, organization: existing.organization, plan: existing.plan, product: existing.product)
        duplicate.valid?
        expect(duplicate.errors.where(:product_id, :taken)).to be_present
      end

      it "allows the same product on a different plan" do
        existing = create(:plan_product)
        other = build(:plan_product, organization: existing.organization, product: existing.product)
        other.valid?
        expect(other.errors.where(:product_id, :taken)).not_to be_present
      end
    end
  end
end
