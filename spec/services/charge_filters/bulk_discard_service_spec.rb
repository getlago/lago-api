# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChargeFilters::BulkDiscardService do
  subject(:service) { described_class.call(charge_filter_ids:) }

  let(:billable_metric) { create(:billable_metric) }
  let(:charge) { create(:standard_charge, billable_metric:) }
  let(:region) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[US Europe]) }
  let(:charge_filter) { create(:charge_filter, charge:) }
  let(:charge_filter_ids) { [charge_filter.id] }

  let(:filter_value) { create(:charge_filter_value, charge_filter:, billable_metric_filter: region, values: %w[US]) }

  before { filter_value }

  it "discards the filter and its values with a single timestamp" do
    expect(service).to be_success

    expect(charge_filter.reload).to be_discarded
    expect(filter_value.reload).to be_discarded
    expect(filter_value.reload.deleted_at).to eq(charge_filter.reload.deleted_at)
    expect(service.discarded_count).to eq(1)
  end

  it "returns a timestamp that selects exactly what the run touched" do
    service

    expect(ChargeFilter.with_discarded.where(deleted_at: service.discarded_at)).to eq([charge_filter])
    expect(ChargeFilterValue.with_discarded.where(deleted_at: service.discarded_at)).to eq([filter_value])
  end

  context "when a timestamp is given" do
    subject(:service) { described_class.call(charge_filter_ids:, discarded_at:) }

    let(:discarded_at) { 2.days.ago.beginning_of_minute }

    it "uses it, so a caller can group several calls into one reversible run" do
      service

      expect(charge_filter.reload.deleted_at).to eq(discarded_at)
      expect(filter_value.reload.deleted_at).to eq(discarded_at)
    end
  end

  context "when a value is already discarded" do
    let(:discarded_value) do
      create(:charge_filter_value, charge_filter:, billable_metric_filter: region, values: %w[Europe])
    end

    before { discarded_value.discard! }

    it "leaves its deleted_at untouched" do
      expect { service }.not_to change { discarded_value.reload.deleted_at }
    end
  end

  context "when the filter is already discarded" do
    before { charge_filter.discard! }

    it "is not counted again" do
      expect(service.discarded_count).to eq(0)
    end
  end

  context "with an empty list" do
    let(:charge_filter_ids) { [] }

    it "does nothing" do
      expect(service.discarded_count).to eq(0)
      expect(charge_filter.reload).not_to be_discarded
    end
  end
end
