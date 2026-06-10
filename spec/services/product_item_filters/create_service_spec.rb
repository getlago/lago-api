# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductItemFilters::CreateService do
  subject(:result) { described_class.call(product_item:, params:) }

  let(:organization) { create(:organization) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:product_item) { create(:product_item, organization:, billable_metric:) }
  let(:region_filter) { create(:billable_metric_filter, organization:, billable_metric:, key: "region", values: %w[us eu]) }
  let(:scheme_filter) { create(:billable_metric_filter, organization:, billable_metric:, key: "scheme", values: %w[visa mastercard]) }

  let(:params) do
    {
      name: "US Visa",
      code: "us_visa",
      description: "US visa transactions",
      invoice_display_name: "US · Visa",
      values: [
        {billable_metric_filter_id: region_filter.id, value: "us"},
        {billable_metric_filter_id: scheme_filter.id, value: "visa"}
      ]
    }
  end

  it "creates a product item filter with its values" do
    expect { result }.to change(ProductItemFilter, :count).by(1)
      .and change(ProductItemFilterValue, :count).by(2)

    filter = result.product_item_filter
    expect(filter.name).to eq("US Visa")
    expect(filter.code).to eq("us_visa")
    expect(filter.description).to eq("US visa transactions")
    expect(filter.invoice_display_name).to eq("US · Visa")
    expect(filter.to_h).to eq("region" => %w[us], "scheme" => %w[visa])
  end

  context "when product_item is nil" do
    let(:product_item) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("product_item")
    end
  end

  context "when product_item is a fixed item" do
    let(:product_item) { create(:product_item, :fixed, organization:) }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:product_item]).to eq(["invalid_item_type"])
    end
  end

  context "when values are missing" do
    before { params[:values] = [] }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:values]).to eq(["value_is_mandatory"])
    end
  end

  context "when a billable metric filter belongs to another metric" do
    let(:other_metric_filter) { create(:billable_metric_filter, organization:) }

    before { params[:values] = [{billable_metric_filter_id: other_metric_filter.id, value: "anything"}] }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:"values.billable_metric_filter_id"]).to eq(["value_is_invalid"])
    end
  end

  context "when the combination is already used on the product item" do
    before do
      described_class.call(
        product_item:,
        params: params.merge(name: "Existing", code: "existing")
      )
    end

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:values]).to eq(["combination_already_exists"])
    end
  end

  context "when a value does not belong to the metric filter values" do
    before { params[:values] = [{billable_metric_filter_id: region_filter.id, value: "mars"}] }

    it "returns a validation failure on the value" do
      expect(result).not_to be_success
      expect(result.error.messages[:"values.value"]).to be_present
    end
  end

  context "when the code is already used on the product item" do
    before { create(:product_item_filter, organization:, product_item:, code: "us_visa") }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:code]).to be_present
    end
  end

  it "produces an activity log" do
    filter = result.product_item_filter
    expect(Utils::ActivityLog).to have_produced("product_item_filter.created").after_commit.with(filter)
  end
end
