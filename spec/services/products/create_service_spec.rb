# frozen_string_literal: true

require "rails_helper"

RSpec.describe Products::CreateService do
  subject(:result) { described_class.call(organization:, params:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:billable_metric) { create(:billable_metric, organization:) }
  let(:product_category) { create(:product_category, organization:) }

  let(:params) do
    {
      product_category_id: product_category.id,
      billable_metric_id: billable_metric.id,
      product_type: "usage",
      name: "Storage",
      code: "storage",
      description: "Object storage",
      invoice_display_name: "Storage (GB)"
    }
  end

  it "creates a usage product" do
    expect { result }.to change(Product, :count).by(1)

    item = result.product
    expect(item.product_category).to eq(product_category)
    expect(item.billable_metric).to eq(billable_metric)
    expect(item.product_type).to eq("usage")
    expect(item.name).to eq("Storage")
    expect(item.code).to eq("storage")
  end

  it "produces an activity log" do
    item = result.product
    expect(Utils::ActivityLog).to have_produced("product.created").after_commit.with(item)
  end

  context "with a fixed item" do
    let(:params) { {product_type: "fixed", name: "Seats", code: "seats"} }

    it "creates a standalone fixed item" do
      expect(result).to be_success
      expect(result.product.product_type).to eq("fixed")
      expect(result.product.product_category).to be_nil
    end
  end

  context "when organization is nil" do
    let(:organization) { nil }
    let(:params) { {product_type: "fixed", name: "Seats", code: "seats"} }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("organization")
    end
  end

  context "when product_category_id does not belong to the organization" do
    before { params[:product_category_id] = create(:product_category).id }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("product_category")
    end
  end

  context "when billable_metric_id does not belong to the organization" do
    before { params[:billable_metric_id] = create(:billable_metric).id }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("billable_metric")
    end
  end

  context "when usage item has no billable metric" do
    before { params[:billable_metric_id] = nil }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:billable_metric]).to be_present
    end
  end

  context "when the code is already used on the product_category" do
    before { create(:product, organization:, product_category:, code: "storage") }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:code]).to be_present
    end
  end
end
