# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecurringAggregationSnapshots::EnqueueBackfillService do
  subject(:result) { described_class.call(organization:, poll_interval: 0) }

  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:billable_metric) { create(:sum_billable_metric, :recurring, organization:) }
  let(:subscription) { create(:subscription, organization:, plan:) }
  let(:queue) { instance_double(Sidekiq::Queue, size: 0) }

  def invoice_period(subscription)
    create(
      :invoice_subscription,
      subscription:,
      invoice: create(:invoice, organization:, customer: subscription.customer),
      invoicing_reason: :subscription_periodic,
      timestamp: Time.zone.parse("2026-10-01"),
      charges_from_datetime: Time.zone.parse("2026-09-01"),
      charges_to_datetime: Time.zone.parse("2026-09-30T23:59:59")
    )
  end

  before do
    create(:standard_charge, plan:, billable_metric:)
    invoice_period(subscription)
    allow(Sidekiq::Queue).to receive(:new).and_return(queue)
  end

  it "enqueues a job per backfillable subscription" do
    expect { result }.to have_enqueued_job(RecurringAggregationSnapshots::BackfillJob).with(subscription).once
    expect(result.subscription_ids).to eq([subscription.id])
    expect(result.contract_ids).to eq([])
  end

  context "with backfillable contracts" do
    let(:contract) { create(:contract, organization:, customer: create(:customer, organization:)) }
    let(:other_contract) { create(:contract, organization:, customer: create(:customer, organization:)) }

    def close_rate_card(contract)
      product = create(:product, :metered, organization:, billable_metric:)
      contract_rate_card = create(:contract_rate_card, organization:, contract:, rate_card: create(:rate_card, organization:, product:))
      create(:billing_operation, organization:, contract_rate_card:, customer: contract.customer,
        action_type: "close_metered_arrears", processed_at: Time.current)
    end

    before do
      close_rate_card(contract)
      close_rate_card(other_contract)
    end

    it "enqueues a job per contract too" do
      expect { result }.to have_enqueued_job(RecurringAggregationSnapshots::BackfillJob).exactly(3).times
      expect(result.subscription_ids).to eq([subscription.id])
      expect(result.contract_ids).to match_array([contract.id, other_contract.id])
    end

    context "with listed contracts" do
      subject(:result) { described_class.call(organization:, contract_ids: [contract.id], poll_interval: 0) }

      it "enqueues them only" do
        expect { result }.to have_enqueued_job(RecurringAggregationSnapshots::BackfillJob).with(contract).once
        expect(result.contract_ids).to eq([contract.id])
      end
    end
  end

  context "with subscriptions that cannot be backfilled" do
    let(:other_organization_subscription) { create(:subscription) }

    before do
      create(:subscription, organization:, plan:)
      invoice_period(create(:subscription, :terminated, organization:, plan:))
      invoice_period(create(:subscription, organization:))
      unique_count_plan = create(:plan, organization:)
      create(:standard_charge, plan: unique_count_plan, billable_metric: create(:unique_count_billable_metric, :recurring, organization:))
      invoice_period(create(:subscription, organization:, plan: unique_count_plan))
      invoice_period(other_organization_subscription)
    end

    it "leaves them out" do
      expect { result }.to have_enqueued_job(RecurringAggregationSnapshots::BackfillJob).once
    end
  end

  context "with listed subscriptions" do
    subject(:result) { described_class.call(organization:, subscription_ids: [subscription.id], poll_interval: 0) }

    before { invoice_period(create(:subscription, organization:, plan:)) }

    it "enqueues them only" do
      expect { result }.to have_enqueued_job(RecurringAggregationSnapshots::BackfillJob).with(subscription).once
      expect(result.subscription_ids).to eq([subscription.id])
    end
  end

  context "with a job already enqueued for the subscription" do
    around do |example|
      ActiveJob::Uniqueness.reset_manager!
      example.run
      ActiveJob::Uniqueness.test_mode!
    end

    before { RecurringAggregationSnapshots::BackfillJob.perform_later(subscription) }

    it "leaves it out of the enqueued subscriptions" do
      expect(result.subscription_ids).to eq([])
    end
  end

  # The queue is shared, so the walk has to stop pushing rather than bury everything else
  it "waits for the queue to drop below the limit before enqueuing" do
    allow(queue).to receive(:size).and_return(5_000, 0)

    described_class.call(organization:, max_queue_size: 10, poll_interval: 0)

    expect(queue).to have_received(:size).twice
  end

  it "checks the queue before each batch" do
    create(:standard_charge, plan:, billable_metric:)
    invoice_period(create(:subscription, organization:, plan:))

    described_class.call(organization:, batch_size: 1, poll_interval: 0)

    expect(queue).to have_received(:size).twice
  end
end
