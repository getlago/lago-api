# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "migrations:billing_operation_snapshots" do # rubocop:disable RSpec/DescribeClass
  subject(:run_task) { task.invoke }

  let(:task) { Rake::Task["migrations:billing_operation_snapshots"] }
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 1, 1)) }
  let(:product) { create(:product, :fixed, organization:) }
  let(:rate_card) { create(:rate_card, organization:, product:, currency: "USD", proration: true) }
  let(:card) do
    create(:contract_rate_card, organization:, contract:, rate_card:,
      effective_date: Date.new(2026, 1, 1), billing_anchor_date: Date.new(2026, 1, 1), billing_scope: :segment)
  end
  let(:rate) { create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 1)) }
  let(:processed_at) { nil }
  let(:invoice) { nil }
  let(:operation) do
    create(:billing_operation, organization:, customer:, contract_rate_card: card,
      action_type: "close_fixed_arrears", billing_at: Time.utc(2026, 2, 1),
      target_cycle_started_at: Time.utc(2026, 1, 1), processed_at:, invoice:)
  end
  let(:dry_run) { "false" }
  let(:organization_filter) { organization.id }
  let(:rows) do
    BillingOperationSegment.where(organization:, billing_operation_id: operation.id).order(:position)
  end

  before do
    travel_to(Time.utc(2026, 1, 1))
    Rake.application.rake_require("tasks/migrations/billing_operation_snapshots")
    Rake::Task.define_task(:environment)
    task.reenable
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ORGANIZATION_ID").and_return(organization_filter)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("DRY_RUN", "true").and_return(dry_run)
    rate
    operation
  end

  it "saves exclusive coverage and ordered segments without changing billing state" do
    original = operation.attributes.except("coverage_started_at", "coverage_ended_at", "updated_at")

    expect { run_task }.to output(/BACKFILL operation=#{operation.id}/).to_stdout

    expect(operation.reload).to have_attributes(
      coverage_started_at: Time.utc(2026, 1, 1), coverage_ended_at: Time.utc(2026, 2, 1)
    )
    expect(operation.attributes.except("coverage_started_at", "coverage_ended_at", "updated_at")).to eq(original)
    expect(rows.map { it.attributes.symbolize_keys.slice(:position, :rate_card_rate_id, :rate_override_id, :started_at, :ended_at, :proration_ratio) }).to eq([
      {position: 0, rate_card_rate_id: rate.id, rate_override_id: nil,
       started_at: Time.utc(2026, 1, 1), ended_at: Time.utc(2026, 2, 1), proration_ratio: 1.to_d}
    ])
  end

  context "with no DRY_RUN setting" do
    let(:dry_run) { "true" }

    it "lists the proposed snapshot without writing anything" do
      expect { run_task }.to output(/DRY RUN operation=#{operation.id}/).to_stdout

      expect(operation.reload).to have_attributes(coverage_started_at: nil, coverage_ended_at: nil)
      expect(rows).to be_empty
    end
  end

  it "does not duplicate or overwrite a completed snapshot on reruns" do
    expect { run_task }.to output(/BACKFILL/).to_stdout
    snapshot = rows.map(&:attributes)
    attributes = operation.reload.attributes
    task.reenable

    expect { task.invoke }.to output(/already snapshotted/).to_stdout

    expect(rows.reload.map(&:attributes)).to eq(snapshot)
    expect(operation.reload.attributes).to eq(attributes)
  end

  context "when the first operation times out waiting for the billing-schedule lock" do
    let(:blocked_operation) do
      create(:billing_operation, id: "00000000-0000-4000-8000-000000000001", organization:, customer:,
        contract_rate_card: card, action_type: operation.action_type, billing_at: operation.billing_at,
        target_cycle_started_at: operation.target_cycle_started_at)
    end

    before do
      blocked_operation
      first_attempt = true
      allow(Customers::LockService).to receive(:call!).and_wrap_original do |original, **args, &block|
        if first_attempt
          first_attempt = false
          raise BaseLockService::FailedToAcquireLock, "lock timed out"
        end
        original.call(**args, &block)
      end
    end

    it "reports the blocked row, finishes the next one, and backfills the missed row on rerun" do
      expect { expect { run_task }.to raise_error(BillingOperationSnapshotsBackfill::UnverifiableOperation, /1 operations/) }
        .to output(/BLOCKED operation=#{blocked_operation.id}: lock timed out.*BACKFILL operation=#{operation.id}/m).to_stdout
      expect(blocked_operation.reload).to have_attributes(coverage_started_at: nil, coverage_ended_at: nil)
      expect(blocked_operation.segments).to be_empty
      expect(rows.count).to eq(1)

      task.reenable
      expect { task.invoke }.to output(/BACKFILL operation=#{blocked_operation.id}/).to_stdout
      expect(blocked_operation.reload).to have_attributes(coverage_started_at: operation.target_cycle_started_at, coverage_ended_at: operation.billing_at)
      expect(blocked_operation.segments.count).to eq(1)
      expect(rows.count).to eq(1)
    end
  end

  context "when filtering another organization" do
    let(:organization_filter) { create(:organization).id }

    it "does not touch operations outside the organization" do
      expect { run_task }.not_to output.to_stdout

      expect(rows).to be_empty
      expect(operation.reload.coverage_started_at).to be_nil
    end
  end

  context "without an organization filter" do
    let(:organization_filter) { nil }

    it "backfills the operation through its organization" do
      expect { run_task }.to output(/BACKFILL/).to_stdout

      expect(rows.count).to eq(1)
    end
  end

  context "with a mid-cycle rate change" do
    let(:later_rate) { create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 15)) }

    before { later_rate }

    it "preserves legacy segment-scoped ownership and proration" do
      expect { run_task }.to output(/BACKFILL/).to_stdout

      expect(rows.map { [it.position, it.rate_card_rate_id, it.started_at, it.ended_at, it.proration_ratio] }).to eq([
        [0, rate.id, Time.utc(2026, 1, 1), Time.utc(2026, 1, 15), BigDecimal(14).div(31, 10)],
        [1, later_rate.id, Time.utc(2026, 1, 15), Time.utc(2026, 2, 1), BigDecimal(17).div(31, 10)]
        # January coverage: 14 days on the original rate, then 17 days, out of 31.
      ])
    end

    context "when the first slice was already billed" do
      let(:previous_operation) do
        create(:billing_operation, organization:, customer:, contract_rate_card: card,
          action_type: "close_fixed_arrears", billing_at: Time.utc(2026, 1, 15),
          target_cycle_started_at: Time.utc(2026, 1, 1), processed_at: Time.utc(2026, 1, 15),
          coverage_started_at: Time.utc(2026, 1, 1), coverage_ended_at: Time.utc(2026, 1, 15))
      end

      before do
        BillingOperationSegment.create!(
          organization:, billing_operation_id: previous_operation.id, rate_card_rate_id: rate.id, position: 0,
          started_at: Time.utc(2026, 1, 1), ended_at: Time.utc(2026, 1, 15), proration_ratio: BigDecimal(14).div(31, 10)
        )
      end

      it "does not attribute the previous operation's coverage again" do
        expect { run_task }.to output(/BACKFILL/).to_stdout

        expect(operation.reload).to have_attributes(
          coverage_started_at: Time.utc(2026, 1, 15), coverage_ended_at: Time.utc(2026, 2, 1)
        )
        expect(rows.map(&:rate_card_rate_id)).to eq([later_rate.id])
      end
    end
  end

  context "with a non-UTC customer" do
    let(:customer) { create(:customer, organization:, timezone: "America/New_York") }
    let(:operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card: card,
        action_type: "close_fixed_arrears", billing_at: Time.utc(2026, 2, 1, 5),
        target_cycle_started_at: Time.utc(2026, 1, 1, 5))
    end

    it "retains customer-local midnight boundaries" do
      expect { run_task }.to output(/BACKFILL/).to_stdout

      expect(operation.reload).to have_attributes(
        coverage_started_at: Time.utc(2026, 1, 1, 5), coverage_ended_at: Time.utc(2026, 2, 1, 5)
      )
    end
  end

  context "when the operation is cancelled" do
    before { operation.update!(cancelled_at: Time.current, cancellation_reason: :rate_change) }

    it "reports cancelled legacy rows that would block a non-null constraint" do
      expect { expect { run_task }.to raise_error(BillingOperationSnapshotsBackfill::UnverifiableOperation) }
        .to output(/BLOCKED.*cancelled/).to_stdout

      expect(rows).to be_empty
      expect(operation.reload.coverage_started_at).to be_nil
    end
  end

  context "with a partial snapshot" do
    before { operation.update!(coverage_started_at: Time.utc(2026, 1, 1)) }

    it "reports a failure without overwriting existing data" do
      expect { expect { run_task }.to raise_error(BillingOperationSnapshotsBackfill::UnverifiableOperation, /1 operations/) }
        .to output(/partial snapshot/).to_stdout

      expect(rows).to be_empty
      expect(operation.reload.coverage_ended_at).to be_nil
    end
  end

  context "when persistence fails" do
    before do
      allow(BillingOperationSegment).to receive(:insert_all!).and_wrap_original do |original, *args|
        original.call(*args)
        raise ActiveRecord::StatementInvalid, "write failed"
      end
    end

    it "rolls back segment rows and coverage together" do
      expect { expect { run_task }.to raise_error(ActiveRecord::StatementInvalid, "write failed") }
        .to output(/BACKFILL/).to_stdout

      expect(rows).to be_empty
      expect(operation.reload).to have_attributes(coverage_started_at: nil, coverage_ended_at: nil)
    end
  end

  context "with a reconciliation operation" do
    before { operation.update!(action_type: "reconcile_advance_coverage", reason: :rate_change) }

    it "does not fabricate historical coverage" do
      expect { expect { run_task }.to raise_error(BillingOperationSnapshotsBackfill::UnverifiableOperation) }
        .to output(/no historical coverage/).to_stdout

      expect(rows).to be_empty
    end
  end

  context "when resolution fails" do
    before { rate.discard! }

    it "reports the failure without persisting coverage" do
      expect { expect { run_task }.to raise_error(BillingOperationSnapshotsBackfill::UnverifiableOperation) }
        .to output(/BLOCKED operation=#{operation.id}/).to_stdout

      expect(operation.reload.coverage_started_at).to be_nil
      expect(rows).to be_empty
    end
  end

  context "when no segment is due" do
    before { operation.update!(billing_at: Time.utc(2026, 1, 20)) }

    it "reports the missing coverage instead of marking the operation as migrated" do
      expect { expect { run_task }.to raise_error(BillingOperationSnapshotsBackfill::UnverifiableOperation) }
        .to output(/returned no coverage/).to_stdout

      expect(rows).to be_empty
      expect(operation.reload.coverage_started_at).to be_nil
    end
  end

  context "with a completed operation" do
    let(:processed_at) { Time.utc(2026, 2, 1) }
    let(:invoice) { create(:invoice, organization:, customer:, invoice_type: :contract) }
    let(:fee_ended_at) { BillingSegment.inclusive_end(Time.utc(2026, 2, 1)) }
    let(:fee) do
      create(:fee, organization:, invoice:, subscription: nil, fee_type: :product,
        contract:, contract_rate_card: card, rate_card_rate: rate,
        invoiceable: product, properties: {
          "from_datetime" => Time.utc(2026, 1, 1).iso8601(6),
          "to_datetime" => fee_ended_at.iso8601(6)
        })
    end

    before { fee }

    it "verifies billed coverage before saving the snapshot" do
      expect { run_task }.to output(/BACKFILL/).to_stdout

      expect(rows.count).to eq(1)
      expect(operation.reload.processed_at).to eq(processed_at)
      expect(operation.invoice_id).to eq(invoice.id)
    end

    context "when the saved coverage differs from the live schedule" do
      let(:fee_ended_at) { BillingSegment.inclusive_end(Time.utc(2026, 1, 15)) }

      it "blocks the operation rather than rewriting historical coverage" do
        expect { expect { run_task }.to raise_error(BillingOperationSnapshotsBackfill::UnverifiableOperation) }
          .to output(/does not match saved invoice fees/).to_stdout

        expect(rows).to be_empty
        expect(operation.reload.coverage_started_at).to be_nil
      end
    end

    context "when pricing configuration changed after billing" do
      before do
        travel_to(Time.utc(2026, 2, 2))
        rate_card.update!(proration: false)
      end

      it "does not infer a historical proration ratio from new settings" do
        expect { expect { run_task }.to raise_error(BillingOperationSnapshotsBackfill::UnverifiableOperation) }
          .to output(/pricing inputs changed/).to_stdout

        expect(rows).to be_empty
      end
    end

    context "when a fee has no coverage" do
      before { fee.update!(properties: {}) }

      it "reports the missing fee snapshot" do
        expect { expect { run_task }.to raise_error(BillingOperationSnapshotsBackfill::UnverifiableOperation) }
          .to output(/fee coverage is missing/).to_stdout

        expect(rows).to be_empty
      end
    end

    context "when a fee has invalid coverage" do
      before { fee.update!(properties: {"from_datetime" => "invalid", "to_datetime" => "invalid"}) }

      it "reports the malformed dates" do
        expect { expect { run_task }.to raise_error(BillingOperationSnapshotsBackfill::UnverifiableOperation) }
          .to output(/fee coverage is invalid/).to_stdout

        expect(rows).to be_empty
      end
    end
  end

  context "with a completed operation without an invoice" do
    let(:processed_at) { Time.utc(2026, 2, 1) }

    it "requires review when no billed coverage was saved" do
      expect { expect { run_task }.to raise_error(BillingOperationSnapshotsBackfill::UnverifiableOperation) }
        .to output(/no invoice to verify/).to_stdout

      expect(rows).to be_empty
    end
  end
end
