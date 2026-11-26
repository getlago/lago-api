# frozen_string_literal: true

require "rails_helper"

RSpec.describe "exports_products view" do # rubocop:disable RSpec/DescribeClass
  let(:organization) { create(:organization) }
  let(:product_category) { create(:product_category, organization:) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:add_on) { create(:add_on, organization:) }

  let(:metered_product) do
    create(:product, organization:, product_category:, billable_metric:, description: "Metered product")
  end
  let(:fixed_product) { create(:product, :fixed, :standalone, organization:, add_on:) }
  let(:deleted_product) { create(:product, organization:, deleted_at: Time.current) }

  let(:result) { ActiveRecord::Base.connection.select_all("SELECT * FROM exports_products") }

  def row_for(product)
    result.to_a.find { |row| row["lago_id"] == product.id }.symbolize_keys
  end

  before do
    metered_product
    fixed_product
    deleted_product
  end

  it "exposes the expected columns" do
    expect(result.columns).to eq(
      %w[
        organization_id
        lago_id
        lago_product_category_id
        lago_billable_metric_id
        lago_add_on_id
        lago_charge_id
        product_type
        code
        name
        invoice_display_name
        description
        created_at
        updated_at
        deleted_at
      ]
    )
  end

  it "exports a metered product with its category and billable metric" do
    metered_product.reload

    expect(row_for(metered_product)).to eq(
      organization_id: organization.id,
      lago_id: metered_product.id,
      lago_product_category_id: product_category.id,
      lago_billable_metric_id: billable_metric.id,
      lago_add_on_id: nil,
      lago_charge_id: nil,
      product_type: "metered",
      code: metered_product.code,
      name: metered_product.name,
      invoice_display_name: nil,
      description: "Metered product",
      created_at: metered_product.created_at,
      updated_at: metered_product.updated_at,
      deleted_at: nil
    )
  end

  it "exports a fixed product with its add-on and no category" do
    expect(row_for(fixed_product)).to include(
      lago_product_category_id: nil,
      lago_billable_metric_id: nil,
      lago_add_on_id: add_on.id,
      product_type: "fixed"
    )
  end

  it "keeps soft-deleted products with their deleted_at" do
    expect(row_for(deleted_product)).to include(deleted_at: Product.with_discarded.find(deleted_product.id).deleted_at)
  end
end
