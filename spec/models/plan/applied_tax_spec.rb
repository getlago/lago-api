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

    describe "database parent guard" do
      it "rejects a row with no plan even past model validation" do
        applied_tax = build(:plan_applied_tax, plan: nil)

        expect { applied_tax.save(validate: false) }.to raise_error(ActiveRecord::StatementInvalid)
      end

      it "rejects a row with both plans even past model validation" do
        applied_tax = create(:plan_applied_tax)
        applied_tax.catalog_plan = create(:catalog_plan, organization: applied_tax.organization)

        expect { applied_tax.save(validate: false) }.to raise_error(ActiveRecord::StatementInvalid)
      end
    end
  end
end
