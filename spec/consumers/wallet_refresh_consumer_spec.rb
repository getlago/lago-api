# frozen_string_literal: true

require "rails_helper"

RSpec.describe WalletRefreshConsumer, clickhouse: {clean_before: true} do
  include_context "with realtime usage availability"

  let(:consumer) { karafka.consumer_for(ENV["LAGO_KAFKA_REALTIME_USAGE_TRIGGERS_TOPIC"]) }

  let(:organization) do
    create(:organization, clickhouse_events_store: true, feature_flags: ["realtime_usage"])
  end
  # No `awaiting_wallet_refresh`: this lane refreshes on the trigger alone, so every example
  # runs against a customer the clock sweep would not pick up.
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:, plan:) }
  let(:billable_metric) { create(:sum_billable_metric, organization:) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }

  let(:other_customer) { create(:customer, organization:) }
  let(:other_wallet) { create(:wallet, customer: other_customer, organization:) }
  let(:other_subscription) { create(:subscription, organization:, customer: other_customer, plan:) }

  let(:last_ingested_at) { Time.current.beginning_of_hour }
  # What the sink actually sends: RisingWave renders a naive timestamp as epoch milliseconds.
  let(:watermark) { (last_ingested_at.to_r * 1000).to_i }

  let(:refresh_options) { {force: true, lock_timeout_seconds: described_class::LOCK_TIMEOUT} }

  before do
    create(:wallet, customer:, organization:)

    # A single pass over the batch, and no real sleeping between passes. The examples that
    # exercise the wait itself raise the timeout back.
    stub_const("#{described_class}::BUCKET_WAIT_TIMEOUT", 0.seconds)
    stub_const("#{described_class}::BUCKET_WAIT_INTERVAL", 0)

    allow(Customers::RefreshWalletsService).to receive(:call!).and_return(Customers::RefreshWalletsService::Result.new)
  end

  def produce(subscription_id: subscription.id, customer_id: customer.id, ingested_at: watermark, **options)
    payload = {
      organization_id: organization.id,
      customer_id:,
      subscription_id:,
      target_wallet_code: "",
      code: billable_metric.code,
      last_ingested_at: ingested_at
    }

    karafka.produce(payload.to_json, options)
  end

  def produce_other(**options)
    produce(customer_id: other_customer.id, subscription_id: other_subscription.id, **options)
  end

  def create_bucket(**attributes)
    create(:clickhouse_usage_bucket, organization:, customer:, subscription:, charge:, billable_metric:, **attributes)
  end

  def create_other_bucket(**attributes)
    create(
      :clickhouse_usage_bucket,
      organization:, customer: other_customer, subscription: other_subscription,
      charge:, billable_metric:, **attributes
    )
  end

  def watermark_result(*subscription_ids)
    RealtimeUsage::BucketWatermarkService::Result.new.tap do |result|
      result.caught_up_subscription_ids = Set.new(subscription_ids)
    end
  end

  # `produced_messages` also holds the triggers these examples produced into the source topic.
  def dlq_messages
    karafka.produced_messages.select { it[:topic] == "unprocessed_wallet_refresh" }
  end

  describe "#consume" do
    context "when the buckets have caught up with the watermark" do
      before { create_bucket(last_ingested_at:) }

      # Throughput comes from the partitions and Karafka's concurrency, not from a job queue.
      it "refreshes the customer inline" do
        produce

        consumer.consume

        expect(Customers::RefreshWalletsService).to have_received(:call!).with(customer:, **refresh_options)
      end

      it "collapses every trigger of one customer into a single refresh" do
        3.times { produce }

        consumer.consume

        expect(Customers::RefreshWalletsService).to have_received(:call!).once
      end

      it "refreshes a trigger produced inside the age window" do
        produce(timestamp: (RealtimeUsage::WalletRefreshTriggersService::MAX_TRIGGER_AGE - 5.seconds).ago)

        consumer.consume

        expect(Customers::RefreshWalletsService).to have_received(:call!).with(customer:, **refresh_options)
      end
    end

    # The refresh is not retried here: the partition is keyed by customer, so a retry would
    # spend it on one customer for usage the sweep picks up in one pass.
    context "when the refresh fails" do
      before do
        create_bucket(last_ingested_at:)

        allow(Customers::RefreshWalletsService).to receive(:call!).and_raise(ActiveRecord::StaleObjectError)
        allow(Sentry).to receive(:capture_exception)

        produce
      end

      it "leaves the customer to the sweep rather than failing the batch" do
        expect { consumer.consume }.not_to raise_error

        expect(dlq_messages).to be_empty
      end

      it "reports the failure" do
        consumer.consume

        expect(Sentry).to have_received(:capture_exception)
      end

      it "keeps refreshing the rest of the batch" do
        other_wallet
        create_other_bucket(last_ingested_at:)

        allow(Customers::RefreshWalletsService)
          .to receive(:call!).with(customer:, **refresh_options).and_raise(ActiveRecord::StaleObjectError)

        produce_other

        consumer.consume

        expect(Customers::RefreshWalletsService).to have_received(:call!).with(customer: other_customer, **refresh_options)
      end
    end

    # Contention means the sweep is refreshing that customer already, which is not a failure.
    context "when the customer's refresh lock is held elsewhere" do
      before do
        create_bucket(last_ingested_at:)

        allow(Customers::RefreshWalletsService).to receive(:call!).and_raise(BaseLockService::FailedToAcquireLock)
        allow(Sentry).to receive(:capture_exception)

        produce
      end

      it "moves on without reporting it" do
        expect { consumer.consume }.not_to raise_error

        expect(Sentry).not_to have_received(:capture_exception)
      end
    end

    # The refreshes run inline, so a batch that overran the poll interval would have the group
    # rebalance under it. What it did not reach is left to the sweep.
    context "when the batch runs out of time" do
      before do
        create_bucket(last_ingested_at:)
        other_wallet
        create_other_bucket(last_ingested_at:)

        stub_const("#{described_class}::CONSUME_DEADLINE", 1.second)

        allow(Customers::RefreshWalletsService).to receive(:call!) { travel(2.seconds) }

        produce
        produce_other
      end

      it "stops refreshing at the deadline" do
        consumer.consume

        expect(Customers::RefreshWalletsService).to have_received(:call!).with(customer:, **refresh_options)
        expect(Customers::RefreshWalletsService).not_to have_received(:call!).with(customer: other_customer, **refresh_options)
      end

      it "does not dead letter what it did not reach" do
        consumer.consume

        expect(dlq_messages).to be_empty
      end
    end

    # A backlog left by a restart or a downtime drains instead of being waited through for
    # usage the clock sweep picks up in one pass.
    context "when the trigger is older than the maximum age" do
      let(:stale) { {timestamp: RealtimeUsage::WalletRefreshTriggersService::MAX_TRIGGER_AGE.ago - 1.second} }

      it "leaves the customer to the clock sweep, even with the buckets caught up" do
        create_bucket(last_ingested_at:)
        produce(**stale)

        consumer.consume

        expect(Customers::RefreshWalletsService).not_to have_received(:call!)
      end
    end

    context "when the buckets are still behind the watermark" do
      before { create_bucket(last_ingested_at: last_ingested_at - 1.second) }

      it "does not refresh" do
        produce

        consumer.consume

        expect(Customers::RefreshWalletsService).not_to have_received(:call!)
      end

      # Waiting longer would hold every other customer on the partition for a wait only this
      # one needs, and ingestion has the customer flagged for the sweep.
      it "leaves the customer to the sweep rather than the dead letter queue" do
        produce

        consumer.consume

        expect(dlq_messages).to be_empty
      end

      it "still refreshes the caught-up customers of the batch" do
        other_wallet
        create_other_bucket(last_ingested_at:)

        produce
        produce_other

        consumer.consume

        expect(Customers::RefreshWalletsService).to have_received(:call!).with(customer: other_customer, **refresh_options)
        expect(Customers::RefreshWalletsService).not_to have_received(:call!).with(customer:, **refresh_options)
      end
    end

    # Trigger and bucket are two sinks of one epoch with no ordering between them, so the
    # buckets of a trigger this fresh are worth a short wait.
    context "when the buckets land during the wait" do
      before do
        create_bucket(last_ingested_at:)

        stub_const("#{described_class}::BUCKET_WAIT_TIMEOUT", 5.seconds)

        allow(RealtimeUsage::BucketWatermarkService)
          .to receive(:call!).and_return(watermark_result, watermark_result(subscription.id))

        produce
      end

      it "refreshes the customer on the cycle its buckets landed" do
        consumer.consume

        expect(Customers::RefreshWalletsService).to have_received(:call!).with(customer:, **refresh_options)
      end

      it "re-reads the watermarks on every cycle" do
        consumer.consume

        expect(RealtimeUsage::BucketWatermarkService).to have_received(:call!).twice
      end
    end

    # The refresh recomputes usage across every active subscription, so one left behind would
    # debit the wallet against its previous epoch.
    context "when the batch carries several subscriptions of one customer" do
      let(:second_subscription) { create(:subscription, organization:, customer:, plan:) }

      before do
        create_bucket(last_ingested_at:)

        produce
        produce(subscription_id: second_subscription.id, ingested_at: watermark - 1_000)
      end

      it "does not refresh while one of them is behind its own watermark" do
        create_bucket(subscription: second_subscription, last_ingested_at: last_ingested_at - 2.seconds)

        consumer.consume

        expect(Customers::RefreshWalletsService).not_to have_received(:call!)
      end

      it "refreshes once every one of them has caught up" do
        create_bucket(subscription: second_subscription, last_ingested_at: last_ingested_at - 1.second)

        consumer.consume

        expect(Customers::RefreshWalletsService).to have_received(:call!).once
      end
    end

    context "when the batch carries several customers" do
      before do
        create_bucket(last_ingested_at:)
        other_wallet
        create_other_bucket(last_ingested_at:)
      end

      # A round-trip per customer would cost more time than the ingestion this reacts to, and
      # the set is re-read on every wait cycle.
      it "reads the bucket watermarks once for the whole batch" do
        allow(RealtimeUsage::BucketWatermarkService).to receive(:call!).and_call_original

        produce
        produce_other

        consumer.consume

        expect(RealtimeUsage::BucketWatermarkService).to have_received(:call!).once
      end
    end

    # An unavailable ClickHouse cannot tell a late bucket from one that will never land, so it
    # must not fail the batch nor refresh against an unknown epoch.
    context "when the bucket watermark read fails" do
      before do
        create_bucket(last_ingested_at:)

        allow(RealtimeUsage::BucketWatermarkService)
          .to receive(:call!).and_raise(ActiveRecord::ActiveRecordError)

        produce
      end

      it "does not refresh" do
        consumer.consume

        expect(Customers::RefreshWalletsService).not_to have_received(:call!)
      end

      it "leaves the batch to the sweep instead of raising out of it" do
        expect { consumer.consume }.not_to raise_error

        expect(dlq_messages).to be_empty
      end
    end

    # The sink does not COALESCE `ingested_at`, and a rendered timestamp would read as an epoch
    # behind every bucket.
    context "when the trigger carries no integer watermark" do
      before { create_bucket(last_ingested_at:) }

      it "does not refresh" do
        produce(ingested_at: nil)

        consumer.consume

        expect(Customers::RefreshWalletsService).not_to have_received(:call!)
      end
    end

    context "when the customer has no active wallet" do
      before do
        create_bucket(last_ingested_at:)
        customer.wallets.update_all(status: :terminated) # rubocop:disable Rails/SkipsModelValidations
      end

      it "does not refresh" do
        produce

        consumer.consume

        expect(Customers::RefreshWalletsService).not_to have_received(:call!)
      end
    end

    context "when the customer has a tax error" do
      before do
        create_bucket(last_ingested_at:)
        create(:error_detail, owner: customer, organization:, error_code: :tax_error)
      end

      it "does not refresh" do
        produce

        consumer.consume

        expect(Customers::RefreshWalletsService).not_to have_received(:call!)
      end
    end

    context "when the organization is outside the realtime usage rollout" do
      let(:organization) { create(:organization, clickhouse_events_store: true) }

      before { create_bucket(last_ingested_at:) }

      it "does not refresh" do
        produce

        consumer.consume

        expect(Customers::RefreshWalletsService).not_to have_received(:call!)
      end
    end

    # Karafka keeps the consumer instance alive across batches, so per-batch state that
    # outlived a `consume` would replay the first batch instead of the one just delivered.
    context "when the consumer instance is reused across batches" do
      before do
        create_bucket(last_ingested_at:)
        other_wallet
        create_other_bucket(last_ingested_at:)

        produce
        consumer.consume
        _karafka_consumer_messages.clear
      end

      it "refreshes the customer carried by the second batch" do
        produce_other(offset: 1)

        consumer.consume

        expect(Customers::RefreshWalletsService).to have_received(:call!).with(customer: other_customer, **refresh_options)
      end

      it "does not replay the first batch" do
        produce_other(offset: 1)

        consumer.consume

        expect(Customers::RefreshWalletsService).to have_received(:call!).with(customer:, **refresh_options).once
      end
    end
  end
end
