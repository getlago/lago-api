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
end
