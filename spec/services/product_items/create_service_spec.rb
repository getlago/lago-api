# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductItems::CreateService do
  subject(:result) { described_class.call(organization:, params:) }

  let(:organization) { create(:organization) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:product) { create(:product, organization:) }

  let(:params) do
    {
      product_id: product.id,
      billable_metric_id: billable_metric.id,
      item_type: "usage",
      name: "Storage",
      code: "storage",
      description: "Object storage",
      invoice_display_name: "Storage (GB)"
    }
  end

  it "creates a usage product item" do
    expect { result }.to change(ProductItem, :count).by(1)

    item = result.product_item
    expect(item.product).to eq(product)
    expect(item.billable_metric).to eq(billable_metric)
    expect(item.item_type).to eq("usage")
    expect(item.name).to eq("Storage")
    expect(item.code).to eq("storage")
  end

  it "produces an activity log" do
    item = result.product_item
    expect(Utils::ActivityLog).to have_produced("product_item.created").after_commit.with(item)
  end

  context "with a fixed item" do
    let(:params) { {item_type: "fixed", name: "Seats", code: "seats"} }

    it "creates a standalone fixed item" do
      expect(result).to be_success
      expect(result.product_item.item_type).to eq("fixed")
      expect(result.product_item.product).to be_nil
    end
  end

  context "when organization is nil" do
    let(:organization) { nil }
    let(:params) { {item_type: "fixed", name: "Seats", code: "seats"} }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("organization")
    end
  end

  context "when product_id does not belong to the organization" do
    before { params[:product_id] = create(:product).id }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("product")
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
      expect(result.error.messages[:billable_metric_id]).to be_present
    end
  end

  context "when the code is already used on the product" do
    before { create(:product_item, organization:, product:, code: "storage") }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:code]).to be_present
    end
  end
end
