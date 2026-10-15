# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductFilters::UpdateService do
  subject(:result) { described_class.call(product_filter:, params:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:billable_metric) { create(:billable_metric, organization:) }
  let(:product) { create(:product, organization:, billable_metric:) }
  let(:region_filter) { create(:billable_metric_filter, organization:, billable_metric:, key: "region", values: %w[us eu]) }

  let(:product_filter) do
    filter = create(:product_filter, organization:, product:, name: "Before", description: "old")
    create(:product_filter_value, organization:, product_filter: filter, billable_metric_filter: region_filter, value: "us")
    filter
  end

  let(:params) { {name: "After", description: "new", invoice_display_name: "Display"} }

  it "updates the filter attributes" do
    expect(result).to be_success
    expect(result.product_filter.name).to eq("After")
    expect(result.product_filter.description).to eq("new")
    expect(result.product_filter.invoice_display_name).to eq("Display")
  end

  it "does not change the values when none are provided" do
    expect { result }.not_to change { product_filter.reload.values.count }
  end

  describe "code editability" do
    let(:params) { {code: "after"} }

    it "updates the code when the item is not in a plan or subscription" do
      expect { result }.to change { product_filter.reload.code }.to("after")
    end
  end

  context "when the item is attached to a plan" do
    before do
      rate_card = create(:rate_card, organization:, product:)
      create(:plan_rate_card, organization:, rate_card:)
    end

    let(:params) { {code: "after", values: [{billable_metric_filter_id: region_filter.id, value: "eu"}]} }

    it "rejects the structural change" do
      expect(result).not_to be_success
      expect(result.error.messages[:code]).to eq(["attached_to_plan_or_subscription"])
      expect(product_filter.reload.to_h).to eq("region" => %w[us])
    end

    it "still updates the display fields without structural params" do
      update_result = described_class.call(product_filter:, params: {name: "renamed"})

      expect(update_result).to be_success
      expect(product_filter.reload.name).to eq("renamed")
    end

    context "when the payload resends the current code and values unchanged" do
      let(:params) do
        {
          name: "renamed",
          code: product_filter.code,
          values: [{billable_metric_filter_id: region_filter.id, value: "us"}]
        }
      end

      it "succeeds without touching the values" do
        expect { result }.not_to change { product_filter.values.order(:id).pluck(:id) }

        expect(result).to be_success
        expect(product_filter.reload.name).to eq("renamed")
      end
    end

    context "when only the values actually change" do
      let(:params) { {values: [{billable_metric_filter_id: region_filter.id, value: "eu"}]} }

      it "replaces the values while no subscription bills through the filter" do
        expect(result).to be_success
        expect(product_filter.reload.to_h).to eq("region" => %w[eu])
      end
    end

    context "when the new values duplicate another filter on the product" do
      before do
        sibling = create(:product_filter, organization:, product:, code: "sibling")
        create(:product_filter_value, organization:, product_filter: sibling, billable_metric_filter: region_filter, value: "eu")
      end

      let(:params) { {values: [{billable_metric_filter_id: region_filter.id, value: "eu"}]} }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:values]).to eq(["value_already_exist"])
        expect(product_filter.reload.to_h).to eq("region" => %w[us])
      end
    end
  end

  context "when a subscription bills through a card scoped to the filter" do
    before do
      rate_card = create(:rate_card, organization:, product:, product_filter:)
      create(:contract_rate_card, organization:, rate_card:)
    end

    let(:params) { {values: [{billable_metric_filter_id: region_filter.id, value: "eu"}]} }

    it "rejects the values change" do
      expect(result).not_to be_success
      expect(result.error.messages[:values]).to eq(["attached_to_subscriptions"])
    end

    it "still accepts a payload resending the current values" do
      update_result = described_class.call(
        product_filter:,
        params: {name: "renamed", values: [{billable_metric_filter_id: region_filter.id, value: "us"}]}
      )

      expect(update_result).to be_success
      expect(product_filter.reload.name).to eq("renamed")
    end

    context "when the payload mixes a key-only entry with a valued entry for the same key" do
      let(:params) do
        {
          values: [
            {billable_metric_filter_id: region_filter.id},
            {billable_metric_filter_id: region_filter.id, value: "eu"}
          ]
        }
      end

      it "rejects the values change instead of crashing on the comparison" do
        expect(result).not_to be_success
        expect(result.error.messages[:values]).to eq(["attached_to_subscriptions"])
      end
    end
  end

  it "produces an activity log" do
    result
    expect(Utils::ActivityLog).to have_produced("product_filter.updated").after_commit.with(product_filter)
  end

  context "when product_filter is nil" do
    let(:product_filter) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("product_filter")
    end
  end

  context "when values are provided" do
    let(:params) { {values: [{billable_metric_filter_id: region_filter.id, value: "eu"}]} }

    it "replaces the existing values" do
      expect(result).to be_success
      expect(result.product_filter.reload.to_h).to eq("region" => %w[eu])
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
