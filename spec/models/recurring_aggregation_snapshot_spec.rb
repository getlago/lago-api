# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecurringAggregationSnapshot do
  subject(:snapshot) { build(:recurring_aggregation_snapshot) }

  describe "associations" do
    it do
      expect(snapshot).to belong_to(:organization)
      expect(snapshot).to belong_to(:subscription)
      expect(snapshot).to belong_to(:charge)
      expect(snapshot).to belong_to(:charge_filter).optional
      expect(snapshot).to belong_to(:billable_metric)
    end
  end

  describe "Scopes" do
    describe ".of_period" do
      let(:snapshot) { create(:recurring_aggregation_snapshot, to_datetime: Time.zone.parse("2026-09-30T23:59:59")) }

      before do
        create(:recurring_aggregation_snapshot, organization: snapshot.organization, subscription: snapshot.subscription,
          charge: snapshot.charge, to_datetime: Time.zone.parse("2026-08-31T23:59:59"))
      end

      it "returns the snapshots of the period the query selects" do
        latest_to_datetime = described_class.order(to_datetime: :desc).limit(1).select(:to_datetime)

        expect(described_class.of_period(latest_to_datetime)).to eq([snapshot])
      end
    end

    describe ".latest_period" do
      let(:marker) { create(:recurring_aggregation_snapshot, to_datetime: Time.zone.parse("2026-09-30T23:59:59")) }
      let(:charge_filter) { create(:charge_filter, charge: marker.charge) }
      let(:bucket_snapshot) { create_snapshot(to_datetime: marker.to_datetime, charge_filter:) }
      let(:older_marker) { create_snapshot(to_datetime: Time.zone.parse("2026-08-31T23:59:59")) }

      def create_snapshot(**attributes)
        create(:recurring_aggregation_snapshot, organization: marker.organization, subscription: marker.subscription, charge: marker.charge, **attributes)
      end

      before do
        bucket_snapshot
        older_marker
        create_snapshot(to_datetime: marker.to_datetime, charge_filter: create(:charge_filter, charge: marker.charge))
      end

      it "returns the snapshots of the listed buckets in the latest period" do
        expect(described_class.latest_period([nil, charge_filter.id])).to match_array([marker, bucket_snapshot])
      end

      it "returns the latest period closed before the given time" do
        expect(described_class.latest_period([nil, charge_filter.id], before: marker.to_datetime)).to eq([older_marker])
      end
    end

    describe ".of_group" do
      let(:marker) { create(:recurring_aggregation_snapshot, grouped_by: {"region" => nil, "cloud" => nil}) }
      let(:charge_filter) { create(:charge_filter, charge: marker.charge) }
      let(:grouped_by_keys) { %w[region cloud] }
      # null sorts before any string in jsonb, so it is the first snapshot of the bucket
      let(:eu_snapshot) { create_snapshot(grouped_by: {"region" => "eu", "cloud" => nil}) }
      let(:eu_aws_snapshot) { create_snapshot(grouped_by: {"region" => "eu", "cloud" => "aws"}) }
      let(:us_aws_snapshot) { create_snapshot(grouped_by: {"region" => "us", "cloud" => "aws"}) }

      def create_snapshot(**attributes)
        create(:recurring_aggregation_snapshot, organization: marker.organization, subscription: marker.subscription,
          charge: marker.charge, charge_filter:, **attributes)
      end

      def of_group(grouped_by_values)
        described_class.of_group(grouped_by_values, grouped_by_keys:, bucket_ids: [nil, charge_filter.id])
      end

      before do
        eu_snapshot
        eu_aws_snapshot
        us_aws_snapshot
      end

      it "returns the snapshots of the group and the first snapshot of each bucket" do
        expect(of_group({"region" => "us", "cloud" => "aws"})).to match_array([marker, eu_snapshot, us_aws_snapshot])
      end

      it "matches a missing value with the null stored for it" do
        expect(of_group({"region" => "eu", "cloud" => nil})).to match_array([marker, eu_snapshot])
      end

      it "matches every value of a key left out" do
        expect(of_group({"region" => "eu"})).to match_array([marker, eu_snapshot, eu_aws_snapshot])
      end

      it "returns every snapshot without grouped_by_values" do
        expect(of_group(nil)).to match_array([marker, eu_snapshot, eu_aws_snapshot, us_aws_snapshot])
      end
    end
  end

  describe "validations" do
    it do
      expect(snapshot).to validate_presence_of(:to_datetime)
      expect(snapshot).to validate_presence_of(:watermark)
      expect(snapshot).to validate_numericality_of(:units)
    end
  end

  describe ".eligible?" do
    subject(:eligible) { described_class.eligible?(metered_item:, billing_context:) }

    let(:billable_metric) { build_stubbed(:sum_billable_metric) }
    let(:billing_segment) { nil }
    let(:metered_item) { instance_double(Fees::ChargeService::MeteredItem, billable_metric:, billing_segment:) }
    let(:billing_context) { Billing::Context.from(subscription: build_stubbed(:subscription)) }

    it { is_expected.to be(true) }

    context "with a weighted sum metric" do
      let(:billable_metric) { build_stubbed(:weighted_sum_billable_metric) }

      it { is_expected.to be(true) }
    end

    context "with another aggregation type" do
      let(:billable_metric) { build_stubbed(:billable_metric, aggregation_type: "count_agg") }

      it { is_expected.to be(false) }
    end

    context "with a contract billing context" do
      let(:billing_context) { Billing::Context.from(contract: build_stubbed(:contract)) }

      it { is_expected.to be(false) }
    end

    context "with a billing segment" do
      let(:billing_segment) { build_stubbed(:billing_segment) }

      it { is_expected.to be(false) }

      context "with a contract billing context" do
        let(:billing_context) { Billing::Context.from(contract: build_stubbed(:contract)) }

        it { is_expected.to be(true) }

        context "with another aggregation type" do
          let(:billable_metric) { build_stubbed(:billable_metric, aggregation_type: "count_agg") }

          it { is_expected.to be(false) }
        end
      end
    end
  end

  describe ".readable?" do
    subject(:readable) { described_class.readable?(metered_item:, billing_context:) }

    let(:organization) { create(:organization) }
    let(:billable_metric) { build_stubbed(:sum_billable_metric, :recurring) }
    let(:metered_item) { instance_double(Fees::ChargeService::MeteredItem, billable_metric:, billing_segment: nil) }
    let(:billing_context) { Billing::Context.from(subscription: build_stubbed(:subscription, organization:)) }

    before { organization.enable_feature_flag!(:persisted_recurring_values) }

    it { is_expected.to be(true) }

    context "without the persisted_recurring_values feature flag" do
      before { organization.disable_feature_flag!(:persisted_recurring_values) }

      it { is_expected.to be(false) }
    end

    context "with a metric that is not recurring" do
      let(:billable_metric) { build_stubbed(:sum_billable_metric) }

      it { is_expected.to be(false) }
    end

    context "with an aggregation type without snapshots" do
      let(:billable_metric) { build_stubbed(:billable_metric, :recurring, aggregation_type: "count_agg") }

      it { is_expected.to be(false) }
    end

    context "with a billing segment in a contract billing context" do
      let(:metered_item) { instance_double(Fees::ChargeService::MeteredItem, billable_metric:, billing_segment: build_stubbed(:billing_segment)) }
      let(:billing_context) { Billing::Context.from(contract: build_stubbed(:contract, organization:)) }

      it { is_expected.to be(true) }

      context "without the persisted_recurring_values feature flag" do
        before { organization.disable_feature_flag!(:persisted_recurring_values) }

        it { is_expected.to be(false) }
      end
    end

    context "with a billing segment in a subscription billing context" do
      let(:metered_item) { instance_double(Fees::ChargeService::MeteredItem, billable_metric:, billing_segment: build_stubbed(:billing_segment)) }

      it { is_expected.to be(false) }
    end
  end

  describe ".key" do
    subject(:key) { described_class.key(metered_item:, billing_context:) }

    let(:subscription) { build_stubbed(:subscription) }
    let(:charge) { build_stubbed(:standard_charge) }
    let(:billing_context) { Billing::Context.from(subscription:) }
    let(:metered_item) { instance_double(Fees::ChargeService::MeteredItem, billing_segment: nil, charge:) }

    it { is_expected.to eq(RecurringAggregationSnapshots::SubscriptionKey.new(subscription:, charge:)) }

    context "with a billing segment" do
      let(:contract) { build_stubbed(:contract) }
      let(:product) { build_stubbed(:product) }
      let(:product_filter) { build_stubbed(:product_filter, product:) }
      let(:rate_card) { build_stubbed(:rate_card, product:, product_filter:) }
      let(:contract_rate_card) { build_stubbed(:contract_rate_card, contract:, rate_card:) }
      let(:billing_context) { Billing::Context.from(contract:) }
      let(:metered_item) do
        instance_double(
          Fees::ChargeService::MeteredItem,
          billing_segment: build_stubbed(:billing_segment), invoiceable: product, contract_rate_card:
        )
      end

      it "keys the snapshots on the contract and the slice its rate card prices" do
        expect(key).to eq(RecurringAggregationSnapshots::ContractKey.new(contract:, product:, product_filter:))
      end

      context "with a rate card without product filter" do
        let(:product_filter) { nil }

        it { is_expected.to eq(RecurringAggregationSnapshots::ContractKey.new(contract:, product:, product_filter: nil)) }
      end
    end
  end

  describe ".fetch_arguments" do
    subject(:arguments) { described_class.fetch_arguments(metered_item:, billing_context:) }

    let(:subscription) { build_stubbed(:subscription) }
    let(:billing_context) { Billing::Context.from(subscription:) }
    let(:charge) { build_stubbed(:standard_charge) }
    let(:charge_filter) { build_stubbed(:charge_filter, charge:) }
    let(:from_datetime) { Time.zone.parse("2026-10-01T00:00:00") }
    let(:boundaries) { instance_double(BillingPeriodBoundaries, charges_from_datetime: from_datetime) }
    let(:metered_item) do
      instance_double(
        Fees::ChargeService::MeteredItem,
        billing_segment: nil, charge:, selected_filter: charge_filter, pricing_group_keys: %w[region], boundaries:
      )
    end

    it "returns the subscription key, filter, grouping keys and period start" do
      expect(arguments).to eq(
        key: RecurringAggregationSnapshots::SubscriptionKey.new(subscription:, charge:),
        filter: charge_filter,
        grouped_by_keys: %w[region],
        from_datetime:,
        period_attributes: {}
      )
    end

    context "with a billing segment" do
      let(:contract) { create(:contract) }
      let(:organization) { contract.organization }
      let(:product) { create(:product, organization:) }
      let(:eu_filter) { create(:product_filter, organization:, product:) }
      let(:us_filter) { create(:product_filter, organization:, product:) }
      let(:rate_card) { create(:rate_card, organization:, product:, product_filter: eu_filter) }
      let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:, effective_date: from_datetime.to_date) }
      let(:billing_context) { Billing::Context.from(contract:) }
      let(:billing_segment) do
        build(:billing_segment, organization:, customer: contract.customer, contract:, contract_rate_card:,
          started_at: from_datetime, ended_at: BillingSegment.inclusive_end(from_datetime + 1.month))
      end
      let(:metered_item) do
        instance_double(
          Fees::ChargeService::MeteredItem,
          billing_segment:, invoiceable: product, contract_rate_card:, selected_filter: eu_filter,
          pricing_group_keys: [], boundaries:
        )
      end

      before do
        create(:contract_rate_card, organization:, contract:, effective_date: from_datetime.to_date,
          rate_card: create(:rate_card, organization:, product:, product_filter: us_filter))
      end

      it "returns the contract key, the product filter and the filters the segment prices" do
        expect(arguments).to eq(
          key: RecurringAggregationSnapshots::ContractKey.new(contract:, product:, product_filter: eu_filter),
          filter: eu_filter,
          grouped_by_keys: [],
          from_datetime:,
          period_attributes: {priced_product_filter_ids: [eu_filter.id, us_filter.id].sort}
        )
      end
    end

    context "with grouping keys given" do
      subject(:arguments) { described_class.fetch_arguments(metered_item:, billing_context:, grouped_by_keys: nil) }

      it "uses them instead of the charge's" do
        expect(arguments[:grouped_by_keys]).to be_nil
      end
    end
  end

  describe ".filters_changed_since?" do
    subject(:filters_changed) { described_class.filters_changed_since?(organization_id: charge.organization_id, charge_ids: charge.id, watermark:) }

    let(:watermark) { Time.zone.parse("2026-10-01T00:05:00") }
    let(:charge) { create(:standard_charge) }
    let(:billable_metric_filter) { create(:billable_metric_filter, billable_metric: charge.billable_metric, values: %w[eu us]) }
    let(:charge_filter) { create(:charge_filter, charge:, created_at: watermark - 1.month) }
    let(:values) { %w[eu] }
    let(:charge_filter_value) do
      create(:charge_filter_value, charge_filter:, billable_metric_filter:, values:, created_at: watermark - 1.month, updated_at: watermark - 1.month)
    end

    before do
      charge_filter_value
      billable_metric_filter.update_columns(updated_at: watermark - 1.month) # rubocop:disable Rails/SkipsModelValidations
    end

    it { is_expected.to be(false) }

    context "when a filter was created after the watermark" do
      before { create(:charge_filter, charge:, created_at: watermark + 1.minute) }

      it { is_expected.to be(true) }
    end

    context "when a filter was removed after the watermark" do
      before { charge_filter.update_columns(deleted_at: watermark + 1.minute) } # rubocop:disable Rails/SkipsModelValidations

      it { is_expected.to be(true) }
    end

    context "when a filter value was edited after the watermark" do
      before { charge_filter_value.update_columns(updated_at: watermark + 1.minute) } # rubocop:disable Rails/SkipsModelValidations

      it { is_expected.to be(true) }
    end

    context "when a filter of another charge changed after the watermark" do
      before { create(:charge_filter, created_at: watermark + 1.minute) }

      it { is_expected.to be(false) }
    end

    context "when the metric filter of a value listing its values changed after the watermark" do
      before { billable_metric_filter.update_columns(updated_at: watermark + 1.minute) } # rubocop:disable Rails/SkipsModelValidations

      it { is_expected.to be(false) }
    end

    context "with a value set to all values of the metric filter" do
      let(:values) { [ChargeFilterValue::ALL_FILTER_VALUES] }

      it { is_expected.to be(false) }

      context "when the metric filter changed after the watermark" do
        before { billable_metric_filter.update_columns(updated_at: watermark + 1.minute) } # rubocop:disable Rails/SkipsModelValidations

        it { is_expected.to be(true) }
      end
    end
  end

  describe "unique index" do
    let(:existing) { create(:recurring_aggregation_snapshot, grouped_by:) }
    let(:grouped_by) { {} }
    let(:duplicate_to_datetime) { existing.to_datetime }
    let(:duplicate) do
      build(
        :recurring_aggregation_snapshot,
        organization: existing.organization,
        subscription: existing.subscription,
        charge: existing.charge,
        charge_filter: existing.charge_filter,
        grouped_by: existing.grouped_by,
        to_datetime: duplicate_to_datetime
      )
    end

    context "without charge filter" do
      it "rejects a second snapshot for the same period, treating NULL filters as equal" do
        expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique)
      end
    end

    context "with grouped_by" do
      let(:grouped_by) { {"region" => "eu"} }

      it "rejects a second snapshot for the same group" do
        expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique)
      end
    end

    context "with a different period" do
      let(:duplicate_to_datetime) { existing.to_datetime + 1.month }

      it "accepts the snapshot" do
        expect { duplicate.save! }.not_to raise_error
      end
    end
  end
end
