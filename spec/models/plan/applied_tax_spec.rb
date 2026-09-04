# frozen_string_literal: true

RSpec.describe Plan::AppliedTax do
  subject(:plan_applied_tax) { create(:plan_applied_tax) }

  describe "associations" do
    it do
      expect(plan_applied_tax).to belong_to(:tax)
      expect(plan_applied_tax).to belong_to(:organization)
      expect(plan_applied_tax).to belong_to(:plan).optional
      expect(plan_applied_tax).to belong_to(:catalog_plan).optional
    end
  end

  describe "validations" do
    describe "exactly_one_plan" do
      it "allows a catalog plan on its own" do
        expect(build(:plan_applied_tax, :catalog_plan)).to be_valid
      end

      it "rejects both a legacy and a catalog plan" do
        applied_tax = build(:plan_applied_tax, catalog_plan: build(:catalog_plan))

        expect(applied_tax).not_to be_valid
        expect(applied_tax.errors.where(:base, :exactly_one_plan_required)).to be_present
      end

      it "rejects neither" do
        applied_tax = build(:plan_applied_tax, plan: nil)

        expect(applied_tax).not_to be_valid
        expect(applied_tax.errors.where(:base, :exactly_one_plan_required)).to be_present
      end
    end
  end
end
