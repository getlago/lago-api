# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecurringAggregationSnapshots::ContractKey do
  subject(:key) { described_class.new(contract:, product:, product_filter:) }

  let(:organization) { create(:organization) }
  let(:contract) { create(:contract, organization:, customer: create(:customer, organization:)) }
  let(:product) { create(:product, organization:) }
  let(:product_filter) { create(:product_filter, organization:, product:) }

  describe "#snapshots" do
    let(:snapshot) { create_snapshot }

    def create_snapshot(**attributes)
      create(:contract_recurring_aggregation_snapshot, organization:, contract:, product:, product_filter:, **attributes)
    end

    before do
      snapshot
      create_snapshot(product_filter: nil)
      create_snapshot(product_filter: create(:product_filter, organization:, product:))
      create_snapshot(product: create(:product, organization:), product_filter: nil)
      create_snapshot(contract: create(:contract, organization:, customer: contract.customer))
    end

    it "returns the snapshots of the contract's product slice only" do
      expect(key.snapshots).to eq([snapshot])
    end
  end

  describe "#bucket_ids" do
    it "returns the product filter's bucket, whatever the filters asked for" do
      expect(key.bucket_ids(nil)).to eq([product_filter.id])
      expect(key.bucket_ids([])).to eq([product_filter.id])
    end

    context "without product filter" do
      let(:product_filter) { nil }

      it "returns the bucket without filter" do
        expect(key.bucket_ids(nil)).to eq([nil])
      end
    end
  end

  describe "#marker_bucket_id" do
    it "returns the product filter's bucket" do
      expect(key.marker_bucket_id).to eq(product_filter.id)
    end
  end

  describe "#bucket_id" do
    it "returns the product filter's bucket" do
      expect(key.bucket_id(product_filter)).to eq(product_filter.id)
    end

    it "refuses another filter's bucket" do
      expect { key.bucket_id(nil) }.to raise_error(ArgumentError)
    end
  end

  describe "#row_attributes" do
    it "returns the key columns but the bucket" do
      expect(key.row_attributes).to eq(
        organization_id: organization.id, contract_id: contract.id, product_id: product.id, billable_metric_id: product.billable_metric_id
      )
    end
  end

  describe "#lock_key" do
    it "names the contract, product, filter and period" do
      expect(key.lock_key(Time.zone.parse("2026-09-30T23:59:59.999999")))
        .to eq("contract-recurring-aggregation-snapshot-#{contract.id}-#{product.id}-#{product_filter.id}-2026-09-30T23:59:59.999999Z")
    end
  end

  describe "#filters_changed_since?" do
    let(:watermark) { Time.zone.parse("2026-10-01T00:05:00") }

    before { product_filter.update_columns(created_at: watermark - 1.month) } # rubocop:disable Rails/SkipsModelValidations

    it "returns false without change of the product's filters since the watermark" do
      expect(key.filters_changed_since?(watermark)).to be(false)
    end

    context "when a filter of the product was created after the watermark" do
      before { create(:product_filter, organization:, product:, created_at: watermark + 1.minute) }

      it "returns true" do
        expect(key.filters_changed_since?(watermark)).to be(true)
      end
    end
  end

  describe "#previous_period" do
    it "returns nothing, as a contract has no predecessor" do
      expect(key.previous_period(filter: product_filter, all_buckets: true, grouped_by_values: nil, grouped_by_keys: [])).to be_nil
    end
  end
end
