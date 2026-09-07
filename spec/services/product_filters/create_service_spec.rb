# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductFilters::CreateService do
  subject(:result) { described_class.call(product:, params:) }

  let(:organization) { create(:organization) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:product) { create(:product, organization:, billable_metric:) }
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

  it "creates a product filter with its values" do
    expect { result }.to change(ProductFilter, :count).by(1)
      .and change(ProductFilterValue, :count).by(2)

    filter = result.product_filter
    expect(filter.name).to eq("US Visa")
    expect(filter.code).to eq("us_visa")
    expect(filter.description).to eq("US visa transactions")
    expect(filter.invoice_display_name).to eq("US · Visa")
    expect(filter.to_h).to eq("region" => %w[us], "scheme" => %w[visa])
  end

  context "when values reference metric filters by key" do
    let(:params) do
      {
        name: "US Visa",
        code: "us_visa_by_key",
        values: [
          {key: region_filter.key, value: "us"},
          {key: scheme_filter.key, value: "visa"}
        ]
      }
    end

    it "resolves the keys to the metric's filters" do
      expect { result }.to change(ProductFilterValue, :count).by(2)
      expect(result.product_filter.to_h).to eq("region" => %w[us], "scheme" => %w[visa])
    end

    context "with an unknown key" do
      let(:params) { {name: "Broken", code: "broken", values: [{key: "unknown", value: "us"}]} }

      it "returns a validation failure on the key" do
        expect(result).not_to be_success
        expect(result.error.messages[:"values.key"]).to eq(["value_is_invalid"])
      end
    end
  end

  context "with a key-only value selection" do
    let(:params) do
      {
        name: "Any region",
        code: "any_region",
        values: [{key: region_filter.key}]
      }
    end

    it "creates the filter matching any value of the key" do
      expect { result }.to change(ProductFilterValue, :count).by(1)

      value = result.product_filter.values.sole
      expect(value.billable_metric_filter).to eq(region_filter)
      expect(value.value).to be_nil
    end
  end

  context "when a key-only entry is combined with specific values for the same key" do
    let(:params) do
      {
        name: "Contradiction",
        code: "contradiction",
        values: [
          {key: region_filter.key},
          {key: region_filter.key, value: "eu"}
        ]
      }
    end

    it "returns a validation failure" do
      expect { result }.not_to change(ProductFilter, :count)

      expect(result).not_to be_success
      expect(result.error.messages[:values]).to eq(["key_only_conflicts_with_values"])
    end
  end

  context "when product is nil" do
    let(:product) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("product")
    end
  end

  context "when product is a fixed item" do
    let(:product) { create(:product, :fixed, organization:) }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:product]).to eq(["not_allowed_for_product_type"])
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
      expect(result.error.messages[:"values.billable_metric_filter"]).to eq(["value_is_invalid"])
    end
  end

  context "when the value set is already used by another filter on the product" do
    before do
      described_class.call(
        product:,
        params: params.merge(name: "Existing", code: "existing")
      )
    end

    it "returns a validation failure" do
      expect { result }.not_to change(ProductFilter, :count)
      expect(result).not_to be_success
      expect(result.error.messages[:values]).to eq(["value_already_exist"])
    end

    it "detects the duplicate regardless of the values order" do
      params[:values] = [
        {billable_metric_filter_id: scheme_filter.id, value: "visa"},
        {billable_metric_filter_id: region_filter.id, value: "us"}
      ]

      expect(result).not_to be_success
      expect(result.error.messages[:values]).to eq(["value_already_exist"])
    end

    it "accepts a differing value set" do
      params[:values] = [{billable_metric_filter_id: region_filter.id, value: "us"}]

      expect(result).to be_success
    end
  end

  context "when a key-only filter for the same key already exists" do
    before do
      described_class.call(
        product:,
        params: params.merge(name: "Existing", code: "existing", values: [{billable_metric_filter_id: region_filter.id}])
      )
    end

    it "rejects a second key-only filter but accepts a valued one" do
      duplicate = described_class.call(
        product:,
        params: params.merge(values: [{billable_metric_filter_id: region_filter.id}])
      )
      expect(duplicate).not_to be_success
      expect(duplicate.error.messages[:values]).to eq(["value_already_exist"])

      valued = described_class.call(
        product:,
        params: params.merge(values: [{billable_metric_filter_id: region_filter.id, value: "eu"}])
      )
      expect(valued).to be_success
    end
  end

  context "when a value does not belong to the metric filter values" do
    before { params[:values] = [{billable_metric_filter_id: region_filter.id, value: "mars"}] }

    it "returns a validation failure on the value" do
      expect(result).not_to be_success
      expect(result.error.messages[:"values.value"]).to be_present
    end
  end

  context "when the code is already used on the product" do
    before { create(:product_filter, organization:, product:, code: "us_visa") }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:code]).to be_present
    end
  end

  it "produces an activity log" do
    filter = result.product_filter
    expect(Utils::ActivityLog).to have_produced("product_filter.created").after_commit.with(filter)
  end
end
