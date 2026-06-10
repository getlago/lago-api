# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductItemFilters::UpdateService do
  subject(:result) { described_class.call(product_item_filter:, params:) }

  let(:organization) { create(:organization) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:product_item) { create(:product_item, organization:, billable_metric:) }
  let(:region_filter) { create(:billable_metric_filter, organization:, billable_metric:, key: "region", values: %w[us eu]) }

  let(:product_item_filter) do
    filter = create(:product_item_filter, organization:, product_item:, name: "Before", description: "old")
    create(:product_item_filter_value, organization:, product_item_filter: filter, billable_metric_filter: region_filter, value: "us")
    filter
  end

  let(:params) { {name: "After", description: "new", invoice_display_name: "Display"} }

  it "updates the filter attributes" do
    expect(result).to be_success
    expect(result.product_item_filter.name).to eq("After")
    expect(result.product_item_filter.description).to eq("new")
    expect(result.product_item_filter.invoice_display_name).to eq("Display")
  end

  it "does not change the values when none are provided" do
    expect { result }.not_to change { product_item_filter.reload.values.count }
  end

  it "produces an activity log" do
    result
    expect(Utils::ActivityLog).to have_produced("product_item_filter.updated").after_commit.with(product_item_filter)
  end

  context "when product_item_filter is nil" do
    let(:product_item_filter) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("product_item_filter")
    end
  end

  context "when values are provided" do
    let(:params) { {values: [{billable_metric_filter_id: region_filter.id, value: "eu"}]} }

    it "replaces the existing values" do
      expect(result).to be_success
      expect(result.product_item_filter.reload.to_h).to eq("region" => %w[eu])
    end

    context "when the new combination matches another filter on the item" do
      before do
        other = create(:product_item_filter, organization:, product_item:)
        create(:product_item_filter_value, organization:, product_item_filter: other, billable_metric_filter: region_filter, value: "eu")
      end

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:values]).to eq(["combination_already_exists"])
      end
    end

    context "when the new combination matches the filter itself" do
      let(:params) { {values: [{billable_metric_filter_id: region_filter.id, value: "us"}]} }

      it "is allowed" do
        expect(result).to be_success
        expect(result.product_item_filter.reload.to_h).to eq("region" => %w[us])
      end
    end

    context "when values are empty" do
      let(:params) { {values: []} }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:values]).to eq(["value_is_mandatory"])
      end
    end
  end
end
