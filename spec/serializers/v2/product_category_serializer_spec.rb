# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::ProductCategorySerializer do
  subject(:payload) { described_class.new(product_category).serialize }

  let(:deleted_at) { nil }
  let(:product_category) do
    create(
      :product_category,
      name: "Compute",
      code: "compute",
      description: "Compute resources",
      invoice_display_name: "Compute usage",
      created_at: Time.zone.parse("2026-03-02T10:00:00Z"),
      updated_at: Time.zone.parse("2026-03-04T12:30:00Z"),
      deleted_at:
    )
  end
  let(:flat_payload) do
    {
      lago_id: product_category.id,
      name: "Compute",
      code: "compute",
      description: "Compute resources",
      invoice_display_name: "Compute usage",
      created_at: "2026-03-02T10:00:00Z",
      updated_at: "2026-03-04T12:30:00Z",
      deleted_at: nil
    }
  end

  it "serializes the product category, with a null deletion timestamp" do
    expect(payload).to eq(flat_payload)
  end

  context "with products" do
    before do
      create_list(:product, 2, organization: product_category.organization, product_category:)
      create(:product, organization: product_category.organization, product_category:, deleted_at: Time.current)
    end

    it "renders no count of them" do
      expect(payload).to eq(flat_payload)
    end
  end

  context "when the product category is deleted" do
    let(:deleted_at) { Time.zone.parse("2026-03-05T08:15:00Z") }

    it "includes the deletion timestamp" do
      expect(payload).to eq(flat_payload.merge(deleted_at: "2026-03-05T08:15:00Z"))
    end
  end
end
