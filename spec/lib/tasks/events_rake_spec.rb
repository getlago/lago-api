# frozen_string_literal: true

require "rails_helper"

require "rake"

RSpec.describe "events:recover_pay_in_advance_fees" do # rubocop:disable RSpec/DescribeClass
  subject(:invoke) { task.invoke }

  let(:task) { Rake::Task["events:recover_pay_in_advance_fees"] }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "sum_agg", field_name: "item_id") }
  let(:charge) do
    create(:standard_charge, :pay_in_advance, plan:, billable_metric:, organization:,
      invoiceable: false, created_at: 10.days.ago)
  end

  let(:subscription) do
    create(:subscription, customer:, organization:, plan:, started_at: 10.days.ago)
  end

  let(:ingested_at) { 3.days.ago.change(usec: 0) }

  let(:event) do
    create(
      :event,
      organization_id: organization.id,
      subscription:,
      code: billable_metric.code,
      properties: {"item_id" => "12"},
      timestamp: ingested_at,
      created_at: ingested_at
    )
  end

  before do
    Rake.application.rake_require("tasks/events")
    Rake::Task.define_task(:environment)
    task.reenable

    charge
    event

    ENV["ORGANIZATION_ID"] = organization.id
    ENV["FROM"] = 4.days.ago.iso8601
    ENV["TO"] = 2.days.ago.iso8601
    ENV["DRY_RUN"] = "false"
  end

  after do
    %w[ORGANIZATION_ID FROM TO DRY_RUN].each { ENV.delete(it) }
  end

  it "re-enqueues the event for pay-in-advance processing" do
    expect { invoke }.to have_enqueued_job(Events::PayInAdvanceJob)
      .with(hash_including("transaction_id" => event.transaction_id, "id" => event.id))
  end

  # Restricted to the fee-creating chain so the `fee.created` webhook is not delivered here.
  it "actually creates the missing fee once the job runs" do
    perform_enqueued_jobs(only: [Events::PayInAdvanceJob, Fees::CreatePayInAdvanceJob]) { invoke }

    fee = Fee.find_by(pay_in_advance_event_transaction_id: event.transaction_id)
    expect(fee).to have_attributes(charge_id: charge.id, subscription_id: subscription.id, units: 12)
  end

  context "when running in dry run mode" do
    before { ENV["DRY_RUN"] = "true" }

    it "does not enqueue anything" do
      expect { invoke }.not_to have_enqueued_job(Events::PayInAdvanceJob)
    end
  end

  # Reporting only is the default, so an operator who forgets DRY_RUN cannot bill anyone.
  context "when DRY_RUN is not set at all" do
    before { ENV.delete("DRY_RUN") }

    it "does not enqueue anything" do
      expect { invoke }.not_to have_enqueued_job(Events::PayInAdvanceJob)
    end
  end

  context "when BATCH_SIZE is not a positive number" do
    before { ENV["BATCH_SIZE"] = "oops" }

    after { ENV.delete("BATCH_SIZE") }

    it "raises instead of silently scanning nothing" do
      expect { invoke }.to raise_error(ArgumentError, /BATCH_SIZE must be positive/)
    end
  end

  context "when the fee already exists without an invoice" do
    before do
      create(
        :charge_fee,
        charge:,
        subscription:,
        organization:,
        invoice: nil,
        pay_in_advance: true,
        pay_in_advance_event_id: event.id,
        pay_in_advance_event_transaction_id: event.transaction_id
      )
    end

    it "does not enqueue anything" do
      expect { invoke }.not_to have_enqueued_job(Events::PayInAdvanceJob)
    end
  end

  # Regression: `Fee.from_organization_pay_in_advance` filters on `invoice_id: nil`, so the guard
  # inside `Events::PayInAdvanceService` cannot see this fee. The task must not rely on it.
  context "when the fee already exists and is attached to an invoice" do
    before do
      create(
        :charge_fee,
        charge:,
        subscription:,
        organization:,
        invoice: create(:invoice, organization:, customer:),
        pay_in_advance: true,
        pay_in_advance_event_id: event.id,
        pay_in_advance_event_transaction_id: event.transaction_id
      )
    end

    it "does not enqueue anything" do
      expect { invoke }.not_to have_enqueued_job(Events::PayInAdvanceJob)
    end
  end

  context "when the only fee was voided" do
    before do
      create(
        :charge_fee,
        charge:,
        subscription:,
        organization:,
        invoice: nil,
        pay_in_advance: true,
        pay_in_advance_event_transaction_id: event.transaction_id
      ).discard!
    end

    it "does not enqueue anything" do
      expect { invoke }.not_to have_enqueued_job(Events::PayInAdvanceJob)
    end
  end

  context "when the charge is not pay in advance" do
    let(:charge) { create(:standard_charge, plan:, billable_metric:, organization:, created_at: 10.days.ago) }

    it "does not enqueue anything" do
      expect { invoke }.not_to have_enqueued_job(Events::PayInAdvanceJob)
    end
  end

  context "when the aggregation requires a field that the event does not carry" do
    let(:event) do
      create(
        :event,
        organization_id: organization.id,
        subscription:,
        code: billable_metric.code,
        properties: {},
        timestamp: 3.days.ago,
        created_at: 3.days.ago
      )
    end

    it "does not enqueue anything" do
      expect { invoke }.not_to have_enqueued_job(Events::PayInAdvanceJob)
    end
  end

  context "when the aggregation needs no field" do
    let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "count_agg") }
    let(:event) do
      create(
        :event,
        organization_id: organization.id,
        subscription:,
        code: billable_metric.code,
        properties: {},
        timestamp: 3.days.ago,
        created_at: 3.days.ago
      )
    end

    it "re-enqueues the event" do
      expect { invoke }.to have_enqueued_job(Events::PayInAdvanceJob)
    end
  end

  # The window is documented as [FROM, TO), so an event ingested exactly at TO is out.
  context "when the event was ingested exactly at the upper bound" do
    before { ENV["TO"] = ingested_at.iso8601 }

    it "does not enqueue anything" do
      expect { invoke }.not_to have_enqueued_job(Events::PayInAdvanceJob)
    end
  end

  context "when the event was ingested exactly at the lower bound" do
    before { ENV["FROM"] = ingested_at.iso8601 }

    it "re-enqueues the event" do
      expect { invoke }.to have_enqueued_job(Events::PayInAdvanceJob)
    end
  end

  context "when a bound is not a parsable datetime" do
    before { ENV["FROM"] = "yesterday" }

    it "raises instead of widening the window" do
      expect { invoke }.to raise_error(ArgumentError, /FROM is not a parsable datetime/)
    end
  end

  context "when the bounds are inverted" do
    before { ENV["FROM"] = 1.day.ago.iso8601 }

    it "raises" do
      expect { invoke }.to raise_error(ArgumentError, /FROM must be earlier than TO/)
    end
  end

  context "when the subscription was terminated before the event" do
    let(:subscription) do
      create(:subscription, customer:, organization:, plan:, started_at: 10.days.ago,
        terminated_at: 5.days.ago, status: :terminated)
    end

    it "does not enqueue anything" do
      expect { invoke }.not_to have_enqueued_job(Events::PayInAdvanceJob)
    end
  end

  # `Events::PostProcessService#subscriptions` excludes incomplete subscriptions, so no fee was
  # created at ingestion time either and there is nothing to recover.
  context "when the subscription is still incomplete" do
    let(:subscription) do
      create(:subscription, customer:, organization:, plan:, started_at: 10.days.ago, status: :incomplete)
    end

    it "does not enqueue anything" do
      expect { invoke }.not_to have_enqueued_job(Events::PayInAdvanceJob)
    end

    it "reports why, rather than dropping the event silently" do
      allow(Rails.logger).to receive(:warn).and_call_original
      invoke

      expect(Rails.logger).to have_received(:warn).with(/its only subscriptions are incomplete/)
    end
  end

  context "when the plan gained a pay-in-advance charge after the event" do
    before { create(:standard_charge, :pay_in_advance, plan:, billable_metric:, organization:, invoiceable: false) }

    it "skips the event rather than billing a charge that did not exist" do
      expect { invoke }.not_to have_enqueued_job(Events::PayInAdvanceJob)
    end

    it "reports why" do
      allow(Rails.logger).to receive(:warn).and_call_original
      invoke

      expect(Rails.logger).to have_received(:warn).with(/gained a pay-in-advance charge/)
    end
  end

  # The gate excludes incomplete subscriptions but `Events::Common#subscription` does not, so the
  # replay would bill a different plan than post-processing would have.
  context "when an incomplete subscription would be billed instead" do
    let(:other_plan) { create(:plan, organization:) }

    before do
      create(:standard_charge, :pay_in_advance, plan: other_plan, billable_metric:, organization:,
        created_at: 10.days.ago)
      create(:subscription, customer:, organization:, plan: other_plan,
        external_id: subscription.external_id, started_at: 10.days.ago, status: :incomplete)
    end

    it "skips the event rather than billing the wrong plan" do
      expect { invoke }.not_to have_enqueued_job(Events::PayInAdvanceJob)
    end

    it "reports the disagreement" do
      allow(Rails.logger).to receive(:warn).and_call_original
      invoke

      expect(Rails.logger).to have_received(:warn).with(/is not the one post-processing would have used/)
    end
  end

  # An upgrade leaves several subscriptions sharing one external_id, and the event must be matched
  # against the one covering its timestamp, not the currently active one.
  context "when the external id is shared with a later subscription" do
    let(:new_plan) { create(:plan, organization:) }

    # Ingested during the outage window, but carrying a timestamp from before the upgrade.
    let(:event) do
      create(
        :event,
        organization_id: organization.id,
        subscription:,
        code: billable_metric.code,
        properties: {"item_id" => "12"},
        timestamp: 6.days.ago,
        created_at: 3.days.ago
      )
    end

    before do
      subscription.update!(terminated_at: 4.days.ago, status: :terminated)
      create(:subscription, customer:, organization:, plan: new_plan, external_id: subscription.external_id,
        started_at: 4.days.ago)
    end

    it "re-enqueues the event against the subscription that covers its timestamp" do
      expect { invoke }.to have_enqueued_job(Events::PayInAdvanceJob)
    end

    context "when only the later subscription carries the pay-in-advance charge" do
      let(:charge) do
        create(:standard_charge, :pay_in_advance, plan: new_plan, billable_metric:, organization:,
          invoiceable: false, created_at: 10.days.ago)
      end

      it "does not enqueue anything" do
        expect { invoke }.not_to have_enqueued_job(Events::PayInAdvanceJob)
      end
    end
  end

  context "when an active and a terminated subscription both cover the timestamp" do
    let(:other_plan) { create(:plan, organization:) }

    before do
      create(:subscription, customer:, organization:, plan: other_plan, external_id: subscription.external_id,
        started_at: 10.days.ago, terminated_at: 1.day.ago, status: :terminated)
    end

    it "prefers the active subscription, whose plan carries the charge" do
      expect { invoke }.to have_enqueued_job(Events::PayInAdvanceJob)
    end
  end

  # `started_at` is nil until activation and NULLS FIRST sorts such a subscription first, so an
  # unguarded in-memory comparison raises before anything is reported.
  context "when a pending subscription shares the external id" do
    before do
      create(:subscription, :pending, customer:, organization:, plan:,
        external_id: subscription.external_id)
    end

    it "re-enqueues the event against the activated subscription" do
      expect { invoke }.to have_enqueued_job(Events::PayInAdvanceJob)
    end
  end

  # The charge associations are declared `with_discarded`, so the joins carry no `deleted_at`
  # predicate and a discarded metric has to be excluded explicitly. `Events::PayInAdvanceService`
  # would resolve no billable metric and create nothing.
  context "when the billable metric is discarded" do
    before { billable_metric.discard! }

    it "does not enqueue anything" do
      expect { invoke }.not_to have_enqueued_job(Events::PayInAdvanceJob)
    end
  end

  # `Plans::DestroyService` discards the plan but not its charges, and `Charge belongs_to :plan,
  # -> { with_discarded }`, so the replay still resolves the charge and creates the fee.
  context "when the plan is discarded" do
    before { plan.discard! }

    it "re-enqueues the event" do
      expect { invoke }.to have_enqueued_job(Events::PayInAdvanceJob)
    end
  end

  context "when the charge is invoiceable" do
    let(:charge) do
      create(:standard_charge, :pay_in_advance, plan:, billable_metric:, organization:, created_at: 10.days.ago)
    end

    it "re-enqueues the event" do
      expect { invoke }.to have_enqueued_job(Events::PayInAdvanceJob)
    end

    it "warns that the replay finalizes invoices and starts payments" do
      allow(Rails.logger).to receive(:warn).and_call_original
      invoke

      expect(Rails.logger).to have_received(:warn).with(/creates 1 invoice\(s\)/)
    end

    # One `Invoices::CreatePayInAdvanceChargeJob` per invoiceable charge, each minting its own
    # invoice, so the count is of charges and not of events.
    context "when the plan carries two invoiceable charges for the metric" do
      before do
        create(:standard_charge, :pay_in_advance, plan:, billable_metric:, organization:,
          created_at: 10.days.ago)
      end

      it "counts one invoice per invoiceable charge" do
        allow(Rails.logger).to receive(:warn).and_call_original
        invoke

        expect(Rails.logger).to have_received(:warn).with(/creates 2 invoice\(s\)/)
      end
    end
  end

  context "when only some of the charges have a fee" do
    let(:other_charge) do
      create(:standard_charge, :pay_in_advance, plan:, billable_metric:, organization:,
        invoiceable: false, created_at: 10.days.ago)
    end

    before do
      create(
        :charge_fee,
        charge: other_charge,
        subscription:,
        organization:,
        invoice: nil,
        pay_in_advance: true,
        pay_in_advance_event_transaction_id: event.transaction_id
      )
    end

    it "skips the event rather than enqueueing a partial replay" do
      expect { invoke }.not_to have_enqueued_job(Events::PayInAdvanceJob)
    end
  end

  context "when the events span several batches" do
    let(:other_events) do
      [2, 1].map do |days|
        create(
          :event,
          organization_id: organization.id,
          subscription:,
          code: billable_metric.code,
          properties: {"item_id" => "12"},
          timestamp: days.days.ago.change(usec: 0),
          created_at: days.days.ago.change(usec: 0)
        )
      end
    end

    before do
      ENV["BATCH_SIZE"] = "1"
      ENV["TO"] = 1.minute.ago.iso8601
      other_events
    end

    after { ENV.delete("BATCH_SIZE") }

    it "walks every batch exactly once, oldest first" do
      invoke

      enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs
        .select { it[:job] == Events::PayInAdvanceJob }
        .map { it[:args].first["transaction_id"] }

      expect(enqueued).to eq([event, *other_events].map(&:transaction_id))
    end
  end

  context "when the organization uses the Clickhouse events store" do
    let(:organization) { create(:organization, clickhouse_events_store: true) }

    it "does not enqueue anything" do
      expect { invoke }.not_to have_enqueued_job(Events::PayInAdvanceJob)
    end
  end
end
