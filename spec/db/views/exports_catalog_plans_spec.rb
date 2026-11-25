# frozen_string_literal: true

require "rails_helper"

RSpec.describe "exports_catalog_plans view" do # rubocop:disable RSpec/DescribeClass
  let(:organization) { create(:organization) }
  let(:catalog_plan) do
    create(
      :catalog_plan,
      organization:,
      invoice_display_name: "Premium plan",
      description: "Monthly premium plan",
      currency: "USD"
    )
  end
  let(:deleted_catalog_plan) { create(:catalog_plan, organization:, deleted_at: Time.current) }

  let(:result) { ActiveRecord::Base.connection.select_all("SELECT * FROM exports_catalog_plans") }

  def row_for(catalog_plan)
    result.to_a.find { |row| row["lago_id"] == catalog_plan.id }.symbolize_keys
  end

  before do
    catalog_plan
    deleted_catalog_plan
  end

  it "exposes the expected columns" do
    expect(result.columns).to eq(
      %w[
        organization_id
        lago_id
        code
        name
        invoice_display_name
        description
        currency
        created_at
        updated_at
        deleted_at
      ]
    )
  end

  it "exports the catalog plan" do
    catalog_plan.reload

    expect(row_for(catalog_plan)).to eq(
      organization_id: organization.id,
      lago_id: catalog_plan.id,
      code: catalog_plan.code,
      name: catalog_plan.name,
      invoice_display_name: "Premium plan",
      description: "Monthly premium plan",
      currency: "USD",
      created_at: catalog_plan.created_at,
      updated_at: catalog_plan.updated_at,
      deleted_at: nil
    )
  end

  it "keeps soft-deleted catalog plans with their deleted_at" do
    expect(row_for(deleted_catalog_plan)).to include(
      deleted_at: CatalogPlan.with_discarded.find(deleted_catalog_plan.id).deleted_at
    )
  end
end
