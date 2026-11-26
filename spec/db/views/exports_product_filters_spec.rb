# frozen_string_literal: true

require "rails_helper"

RSpec.describe "exports_product_filters view" do # rubocop:disable RSpec/DescribeClass
  let(:organization) { create(:organization) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:product) { create(:product, organization:, billable_metric:) }
  let(:region_filter) do
    create(:billable_metric_filter, organization:, billable_metric:, key: "region", values: %w[us eu apac])
  end
  let(:cloud_filter) do
    create(:billable_metric_filter, organization:, billable_metric:, key: "cloud", values: %w[aws gcp])
  end

  let(:product_filter) { create(:product_filter, organization:, product:) }
  let(:empty_product_filter) { create(:product_filter, organization:, product:) }

  let(:result) { ActiveRecord::Base.connection.select_all("SELECT * FROM exports_product_filters") }

  def row_for(product_filter)
    row = result.to_a.find { |r| r["lago_id"] == product_filter.id }.symbolize_keys
    row.merge(filter_values: JSON.parse(row[:filter_values]))
  end

  def create_value(billable_metric_filter, value, **attributes)
    create(:product_filter_value, organization:, product_filter:, billable_metric_filter:, value:, **attributes)
  end

  before do
    travel_to(2.days.ago) do
      product_filter
      empty_product_filter
    end
  end

  it "exposes the expected columns" do
    expect(result.columns).to eq(
      %w[
        organization_id
        lago_id
        lago_product_id
        code
        name
        description
        invoice_display_name
        created_at
        updated_at
        deleted_at
        filter_values
      ]
    )
  end

  it "folds the kept values in with their billable metric filter key" do
    create_value(region_filter, "eu")
    create_value(cloud_filter, nil) # nil selects every value of the billable metric filter
    create_value(region_filter, "us", deleted_at: Time.current)
    product_filter.reload

    expect(row_for(product_filter)).to eq(
      organization_id: organization.id,
      lago_id: product_filter.id,
      lago_product_id: product.id,
      code: product_filter.code,
      name: product_filter.name,
      description: "test description",
      invoice_display_name: product_filter.invoice_display_name,
      created_at: product_filter.created_at,
      updated_at: ProductFilterValue.unscoped.where(product_filter:).maximum(:updated_at),
      deleted_at: nil,
      filter_values: [
        {"key" => "region", "value" => "eu"},
        {"key" => "cloud", "value" => nil}
      ]
    )
  end

  it "takes the filter's updated_at when it has no values" do
    expect(row_for(empty_product_filter)).to include(
      updated_at: empty_product_filter.reload.updated_at,
      filter_values: []
    )
  end

  it "moves updated_at when a value is removed" do
    value = travel_to(1.day.ago) { create_value(region_filter, "eu") }
    value.discard!

    expect(row_for(product_filter)).to include(
      updated_at: value.reload.updated_at,
      filter_values: []
    )
  end

  it "keeps soft-deleted filters with their deleted_at" do
    product_filter.discard!

    expect(row_for(product_filter)).to include(deleted_at: product_filter.reload.deleted_at)
  end
end
