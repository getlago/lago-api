# frozen_string_literal: true

require "rails_helper"

RSpec.describe "exports_plans_taxes view" do # rubocop:disable RSpec/DescribeClass
  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:tax) { create(:tax, organization:) }
  let!(:plan_applied_tax) { create(:plan_applied_tax, plan:, tax:, organization:) }
  let!(:catalog_plan_applied_tax) { create(:plan_applied_tax, :catalog_plan, tax:, organization:) }

  it "exposes the taxes of plans and catalog plans with their parent and tax ids" do
    rows = ActiveRecord::Base.connection.select_all("SELECT * FROM exports_plans_taxes").map(&:symbolize_keys)

    expect(rows).to contain_exactly(
      {
        organization_id: organization.id,
        lago_id: plan_applied_tax.id,
        lago_plan_id: plan.id,
        lago_catalog_plan_id: nil,
        lago_tax_id: tax.id,
        created_at: plan_applied_tax.reload.created_at,
        updated_at: plan_applied_tax.updated_at
      },
      {
        organization_id: organization.id,
        lago_id: catalog_plan_applied_tax.id,
        lago_plan_id: nil,
        lago_catalog_plan_id: catalog_plan_applied_tax.catalog_plan_id,
        lago_tax_id: tax.id,
        created_at: catalog_plan_applied_tax.reload.created_at,
        updated_at: catalog_plan_applied_tax.updated_at
      }
    )
  end
end
