# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecurringAggregationSnapshots::ContractBackfillService do
  subject(:result) { described_class.call(contract:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 2, 1)) }
  let(:metric) { create(:sum_billable_metric, :recurring, organization:, field_name: "quantity") }
  let(:product) { create(:product, :metered, organization:, billable_metric: metric) }
  let(:rate_card) { create(:rate_card, organization:, product:, currency: "USD") }
  let(:contract_rate_card) do
    create(:contract_rate_card, organization:, contract:, rate_card:, effective_date: Date.new(2026, 2, 1), billing_anchor_date: Date.new(2026, 2, 1))
  end
  let(:snapshots) { ContractRecurringAggregationSnapshot.where(contract:, product:) }
  let(:now) { Time.utc(2026, 3, 10) }
  let(:february_end) { BillingSegment.inclusive_end(Time.utc(2026, 3, 1)) }

  def create_usage(quantity, timestamp)
    create(:event, organization:, customer:, external_subscription_id: contract.external_id, code: metric.code,
      timestamp:, created_at: Time.utc(2026, 1, 1), properties: {quantity:})
  end

  around { |example| travel_to(now) { example.run } }

  before do
    create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 1), rate_model: "standard", rate_properties: {"amount" => "10"})
    create_usage(3, Time.utc(2026, 1, 20))
    create_usage(2, Time.utc(2026, 2, 10))
    create_usage(4, Time.utc(2026, 3, 5))

    create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "close_metered_arrears",
      billing_at: Time.utc(2026, 3, 1), target_cycle_started_at: Time.utc(2026, 2, 1))
    # Writes off: the close bills the period without writing its snapshot
    BillingOperations::ProcessService.call!(customer:, timestamp: Time.utc(2026, 3, 1))
  end

  it "writes the snapshot of the latest slice the rate card closed" do
    expect(result).to be_success
    expect(result.written_rate_cards).to eq([contract_rate_card])
    expect(result.skipped_rate_cards).to eq([])
    expect(result.failed_rate_cards).to eq([])

    # 3 in January + 2 in February, recurring; the March event is after the slice
    expect(snapshots.sole).to have_attributes(
      product_filter_id: nil,
      to_datetime: february_end,
      watermark: now - RecurringAggregationSnapshot::WATERMARK_LAG,
      units: 5,
      events_count: 2,
      priced_product_filter_ids: []
    )
  end

  it "creates no fee" do
    expect { result }.not_to change(Fee, :count)
  end

  context "with a rate change inside the cycle" do
    let(:now) { Time.utc(2026, 4, 10) }

    before do
      create(:rate_card_rate, organization:, rate_card:, code: "after-midcycle", effective_from: Time.utc(2026, 3, 15),
        rate_model: "standard", rate_properties: {"amount" => "20"})
      create_usage(1, Time.utc(2026, 3, 20))

      # Processes the successor of the February close, which bills both March slices
      BillingOperations::ProcessService.call!(customer:, timestamp: Time.utc(2026, 4, 1))
    end

    it "writes the last slice of the latest close only" do
      result

      # 5 up to March + 4 on 5 March + 1 on 20 March: the slice from the rate change to the cycle end
      expect(snapshots.sole).to have_attributes(to_datetime: BillingSegment.inclusive_end(Time.utc(2026, 4, 1)), units: 10, events_count: 4)
    end
  end

  context "with a snapshot already stored for the slice" do
    before do
      create(:contract_recurring_aggregation_snapshot, organization:, contract:, product:, to_datetime: february_end,
        watermark: Time.utc(2026, 3, 2), units: 99, events_count: 9)
    end

    it "replaces it" do
      result

      expect(snapshots.sole).to have_attributes(units: 5, events_count: 2)
    end
  end

  context "when the slice has no units" do
    before { Event.where(organization:).delete_all }

    it "writes a zero marker" do
      expect(result.written_rate_cards).to eq([contract_rate_card])
      expect(snapshots.sole).to have_attributes(to_datetime: february_end, units: 0, events_count: 0)
    end
  end

  context "without a processed close operation" do
    before { BillingOperation.where(organization:).update_all(processed_at: nil, updated_at: Time.current) } # rubocop:disable Rails/SkipsModelValidations

    it "writes nothing" do
      expect(result.written_rate_cards).to eq([])
      expect(snapshots).to be_empty
    end
  end

  context "with a rate card on a non recurring metric" do
    let(:metric) { create(:sum_billable_metric, organization:, field_name: "quantity") }

    it "leaves it out" do
      expect(result.written_rate_cards).to eq([])
      expect(result.skipped_rate_cards).to eq([])
      expect(snapshots).to be_empty
    end
  end

  context "when the events store fails" do
    before do
      allow(Fees::ChargeService).to receive(:call).and_raise(ActiveRecord::StatementInvalid)
    end

    it "reports the rate card as failed" do
      expect(result).to be_success
      expect(result.failed_rate_cards).to eq([contract_rate_card])
    end
  end

  context "when the slices cannot be rebuilt" do
    before do
      allow(BillingOperations::ResolveSegmentsService).to receive(:call!)
        .and_raise(BaseService::FailedResult.new(BaseResult.new, "schedule failed"))
    end

    it "reports the rate card as failed" do
      expect(result.failed_rate_cards).to eq([contract_rate_card])
    end
  end

  context "when the contract is no longer active" do
    before { contract.update!(status: :terminated, terminated_at: now) }

    it "fails" do
      expect(result).to be_failure
      expect(result.error.code).to eq("contract_not_active")
    end
  end

  describe ".backfillable_contracts" do
    subject(:backfillable_contracts) { described_class.backfillable_contracts(organization) }

    let(:other_contract) { create(:contract, organization:, customer:) }

    before do
      # Never closed
      create(:contract_rate_card, organization:, contract: other_contract, rate_card: create(:rate_card, organization:, product:, currency: "USD"))
      # Closed, but in another organization
      create(:billing_operation, action_type: "close_metered_arrears", processed_at: now)
    end

    it "returns the active contracts with a closed recurring sum rate card" do
      expect(backfillable_contracts).to eq([contract])
    end
  end
end
