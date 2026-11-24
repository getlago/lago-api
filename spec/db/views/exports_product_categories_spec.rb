# frozen_string_literal: true

require "rails_helper"

RSpec.describe "exports_product_categories view" do # rubocop:disable RSpec/DescribeClass
  let(:organization) { create(:organization) }
  let(:product_category) { create(:product_category, organization:) }
  let(:deleted_product_category) { create(:product_category, organization:, deleted_at: Time.current) }

  let(:result) { ActiveRecord::Base.connection.select_all("SELECT * FROM exports_product_categories") }

  def row_for(product_category)
    result.to_a.find { |row| row["lago_id"] == product_category.id }.symbolize_keys
  end

  before do
    product_category
    deleted_product_category
  end

  it "exports the product category" do
    product_category.reload

    expect(row_for(product_category)).to eq(
      organization_id: organization.id,
      lago_id: product_category.id,
      code: product_category.code,
      name: product_category.name,
      description: "test description",
      invoice_display_name: product_category.invoice_display_name,
      created_at: product_category.created_at,
      updated_at: product_category.updated_at,
      deleted_at: nil
    )
  end

  it "keeps soft-deleted product categories with their deleted_at" do
    expect(row_for(deleted_product_category)).to include(
      deleted_at: ProductCategory.with_discarded.find(deleted_product_category.id).deleted_at
    )
  end
end
