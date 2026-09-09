# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::BillingPeriodFilters::MatchingAndIgnoredService do
  subject(:service_result) { described_class.call(target_filter:) }

  let(:billable_metric) { create(:billable_metric) }
  let(:charge) { create(:standard_charge, billable_metric:) }
  let(:target_filter) { Events::BillingPeriodFilters::FilterTarget.from_charge(charge:, filter: parent_filter) }
  let(:size_filter) { create(:billable_metric_filter, billable_metric:, key: "size", values: %w[512 1024]) }
  let(:parent_filter) { create(:charge_filter, charge:) }
  let(:child_filter) { create(:charge_filter, charge:) }

  before do
    create(:charge_filter_value, values: %w[512 1024], billable_metric_filter: size_filter, charge_filter: parent_filter)
    create(:charge_filter_value, values: ["512"], billable_metric_filter: size_filter, charge_filter: child_filter)
  end

  it "returns matching values and ignored child filters through the generic target" do
    expect(service_result.matching_filters).to eq({"size" => %w[512 1024]})
    expect(service_result.ignored_filters).to eq([{"size" => ["512"]}])
  end

  context "with a billing segment target selecting all configured values" do
    let(:organization) { billable_metric.organization }
    let(:product) { create(:product, organization:, billable_metric:) }
    let(:contract) { create(:contract, organization:) }
    let(:rate_card) { create(:rate_card, organization:, product:) }
    let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }
    let(:rate_card_rate) { create(:rate_card_rate, organization:, rate_card:) }
    let(:billing_segment) do
      create(:billing_segment, organization:, customer: contract.customer, contract:, contract_rate_card:, rate_card_rate:)
    end
    let(:product_filter) { create(:product_filter, organization:, product:) }
    let(:child_product_filter) { create(:product_filter, organization:, product:) }
    let(:target_filter) do
      Events::BillingPeriodFilters::FilterTarget.from_billing_segment(billing_segment:, filter: product_filter)
    end

    before do
      create(:product_filter_value, organization:, product_filter:, billable_metric_filter: size_filter, value: nil)
      create(:product_filter_value, organization:, product_filter: child_product_filter,
        billable_metric_filter: size_filter, value: "512")
    end

    it "expands matching values and ignores the explicit child filter" do
      expect(service_result.matching_filters).to eq({"size" => %w[512 1024]})
      expect(service_result.ignored_filters).to eq([{"size" => ["512"]}])
      expect(target_filter.all_filter_values?(product_filter, "size")).to be(true)
      expect(target_filter.all_filter_values?(child_product_filter, "size")).to be(false)
    end
  end
end
