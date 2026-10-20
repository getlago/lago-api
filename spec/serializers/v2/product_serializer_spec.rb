# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::ProductSerializer do
  subject(:payload) { described_class.new(product, options).serialize }

  let(:product_category) { create(:product_category) }
  let(:product) { create(:product, organization: product_category.organization, product_category:) }
  let(:options) { {} }
  let(:flat_payload) do
    {
      lago_id: product.id,
      product_category_code: product_category.code,
      billable_metric_code: product.billable_metric.code,
      name: product.name,
      code: product.code,
      description: product.description,
      invoice_display_name: product.invoice_display_name,
      product_type: "metered",
      created_at: product.created_at.iso8601,
      updated_at: product.updated_at.iso8601,
      deleted_at: nil
    }
  end

  it "serializes the product, without counts nor expansions" do
    expect(payload).to eq(flat_payload)
  end

  context "when the product has filters" do
    before { create(:product_filter, organization: product.organization, product:) }

    it "renders no filters count" do
      expect(payload).to eq(flat_payload)
    end
  end

  # Passed by the activity log only.
  context "with the counts option" do
    let(:options) { {includes: %i[counts]} }

    before do
      create(:product_filter, organization: product.organization, product:)
      create(:product_filter, organization: product.organization, product:, deleted_at: Time.current)
    end

    it "renders the count of the kept filters, right after the product type" do
      expect(payload).to eq(flat_payload.merge(filters_count: 1))
      expect(payload.keys.index(:filters_count)).to eq(payload.keys.index(:product_type) + 1)
    end
  end

  context "with the product_category expansion" do
    let(:options) { {includes: %i[product_category]} }

    it "embeds the product category" do
      expect(payload).to eq(
        flat_payload.merge(
          product_category: {
            lago_id: product_category.id,
            name: product_category.name,
            code: product_category.code,
            description: product_category.description,
            invoice_display_name: product_category.invoice_display_name,
            products_count: 1,
            created_at: product_category.created_at.iso8601,
            updated_at: product_category.updated_at.iso8601,
            deleted_at: nil
          }
        )
      )
    end
  end

  context "with the billable_metric expansion" do
    let(:options) { {includes: %i[billable_metric]} }

    it "embeds the billable metric as V2::BillableMetricSerializer renders it" do
      expect(payload).to eq(flat_payload.merge(billable_metric: V2::BillableMetricSerializer.new(product.billable_metric).serialize))
    end
  end
end
