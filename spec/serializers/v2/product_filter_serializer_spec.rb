# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::ProductFilterSerializer do
  subject(:payload) { described_class.new(product_filter).serialize }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:product_category, refind: true) { create(:product_category, organization:, code: "compute") }
  let_it_be(:product, refind: true) { create(:product, organization:, product_category:, code: "api") }
  let_it_be(:region_filter) do
    create(:billable_metric_filter, billable_metric: product.billable_metric, key: "region", values: %w[us eu apac])
  end
  let_it_be(:tier_filter) do
    create(:billable_metric_filter, billable_metric: product.billable_metric, key: "tier", values: %w[free pro])
  end

  let(:product_filter) do
    create(
      :product_filter,
      organization:,
      product:,
      name: "Europe",
      code: "europe",
      description: "Usage in the European region",
      invoice_display_name: "Europe usage",
      created_at: Time.zone.parse("2026-01-05T10:00:00Z"),
      updated_at: Time.zone.parse("2026-01-06T11:30:00Z"),
      deleted_at:
    )
  end
  let(:deleted_at) { nil }
  let(:flat_payload) do
    {
      lago_id: product_filter.id,
      product_code: "api",
      product_category_code: "compute",
      name: "Europe",
      code: "europe",
      description: "Usage in the European region",
      invoice_display_name: "Europe usage",
      values: [],
      created_at: "2026-01-05T10:00:00Z",
      updated_at: "2026-01-06T11:30:00Z",
      deleted_at: nil
    }
  end

  it "serializes the filter, with a null deletion timestamp" do
    expect(payload).to eq(flat_payload)
  end

  context "with values" do
    before do
      create(
        :product_filter_value,
        organization:,
        product_filter:,
        billable_metric_filter: region_filter,
        value: "eu",
        created_at: Time.zone.parse("2026-01-05T10:00:00Z")
      )
      # A null value selects every value of the billable metric filter
      create(
        :product_filter_value,
        organization:,
        product_filter:,
        billable_metric_filter: tier_filter,
        value: nil,
        created_at: Time.zone.parse("2026-01-05T10:01:00Z")
      )
    end

    it "renders each value with the key of its billable metric filter" do
      expect(payload).to eq(
        flat_payload.merge(
          values: [
            {key: "region", value: "eu"},
            {key: "tier", value: nil}
          ]
        )
      )
    end
  end

  context "when the filter belongs to another product and category" do
    let(:product_filter) do
      other_category = create(:product_category, organization:, code: "storage")
      other_product = create(:product, organization:, product_category: other_category, code: "s3")

      create(
        :product_filter,
        organization:,
        product: other_product,
        name: "Europe",
        code: "europe",
        description: "Usage in the European region",
        invoice_display_name: "Europe usage",
        created_at: Time.zone.parse("2026-01-05T10:00:00Z"),
        updated_at: Time.zone.parse("2026-01-06T11:30:00Z")
      )
    end

    it "renders the codes of its own product and category" do
      expect(payload).to eq(flat_payload.merge(product_code: "s3", product_category_code: "storage"))
    end
  end

  context "when its product and category are deleted" do
    before do
      product.discard!
      product_category.discard!
    end

    it "still renders their codes" do
      expect(payload).to eq(flat_payload)
    end
  end

  context "when the filter is deleted" do
    let(:deleted_at) { Time.zone.parse("2026-02-01T09:00:00Z") }

    it "includes the deletion timestamp" do
      expect(payload).to eq(flat_payload.merge(deleted_at: "2026-02-01T09:00:00Z"))
    end

    context "with a value still kept" do
      before { create(:product_filter_value, organization:, product_filter:, billable_metric_filter: region_filter, value: "eu") }

      it "renders no value" do
        expect(payload).to eq(flat_payload.merge(deleted_at: "2026-02-01T09:00:00Z"))
      end
    end
  end
end
