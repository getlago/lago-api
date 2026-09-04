# frozen_string_literal: true

require "rails_helper"

RSpec.describe WalletRefreshConsumer, clickhouse: {clean_before: true} do
  include_context "with realtime usage availability"

  # Not a `subject`: `pause` and `mark_as_consumed` reach Kafka through a client the testing
  # gem does not fake, so both have to be stubbed on the consumer itself.
  let(:consumer) { karafka.consumer_for(ENV["LAGO_KAFKA_REALTIME_USAGE_TRIGGERS_TOPIC"]) }

  let(:organization) do
    create(:organization, clickhouse_events_store: true, feature_flags: ["realtime_usage"])
  end
  # No `awaiting_wallet_refresh`: this lane dispatches on the trigger alone, so every example
  # runs against a customer the clock sweep would not pick up.
  let(:customer) { create(:customer, organization:) }
  let!(:wallet) { create(:wallet, customer:, organization:) }
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

  before { allow(consumer).to receive(:pause) }

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

  # `produced_messages` also holds the triggers these examples produced into the source topic.
  def dlq_messages
    karafka.produced_messages.select { it[:topic] == "unprocessed_wallet_refresh" }
  end

  describe "#consume" do
    context "when the buckets have caught up with the watermark" do
      before { create_bucket(last_ingested_at:) }

      # The wallet ids are what make the job run for a customer the sweep has not flagged.
      it "enqueues the refresh with the customer's active wallet ids" do
        produce

        expect { consumer.consume }
          .to have_enqueued_job(Customers::RefreshWalletJob).with(customer, wallet_ids: [wallet.id])
      end

      it "collapses every trigger of one customer into a single refresh" do
        3.times { produce }

        expect { consumer.consume }.to have_enqueued_job(Customers::RefreshWalletJob).once
      end

      it "tolerates a watermark sent as a timestamp string" do
        produce(ingested_at: last_ingested_at.utc.iso8601(3))

        expect { consumer.consume }.to have_enqueued_job(Customers::RefreshWalletJob)
      end

      it "does not pause the partition" do
        produce
        consumer.consume

        expect(consumer).not_to have_received(:pause)
      end

      it "refreshes a trigger produced inside the age window" do
        produce(timestamp: (described_class::MAX_TRIGGER_AGE - 5.seconds).ago)

        expect { consumer.consume }
          .to have_enqueued_job(Customers::RefreshWalletJob).with(customer, wallet_ids: [wallet.id])
      end
    end

    # A backlog left by a restart or a downtime drains instead of being waited through, one
    # offset at a time, for usage the clock sweep picks up in one pass.
    context "when the trigger is older than the maximum age" do
      let(:stale) { {timestamp: described_class::MAX_TRIGGER_AGE.ago - 1.second} }

      it "leaves the customer to the clock sweep, even with the buckets caught up" do
        create_bucket(last_ingested_at:)
        produce(**stale)

        expect { consumer.consume }.not_to have_enqueued_job(Customers::RefreshWalletJob)
      end

      it "does not pause, even with the buckets behind" do
        create_bucket(last_ingested_at: last_ingested_at - 1.second)
        produce(**stale)

        consumer.consume

        expect(consumer).not_to have_received(:pause)
      end
    end

    context "when the buckets are still behind the watermark" do
      before { create_bucket(last_ingested_at: last_ingested_at - 1.second) }

      it "does not enqueue the refresh" do
        produce

        expect { consumer.consume }.not_to have_enqueued_job(Customers::RefreshWalletJob)
      end

      it "pauses on the customer's first offset instead of waiting" do
        produce
        produce

        consumer.consume

        expect(consumer).to have_received(:pause).with(0, described_class::WATERMARK_PAUSE_TIMEOUT)
      end

      # Pausing re-delivers the whole batch, so without a record of what it already refreshed
      # every caught-up customer of the batch would cost a refresh per cycle.
      it "does not refresh a caught-up customer again on the next cycle" do
        other_wallet
        create_other_bucket(last_ingested_at:)

        produce_other
        produce

        expect { 2.times { consumer.consume } }
          .to have_enqueued_job(Customers::RefreshWalletJob).with(other_customer, wallet_ids: [other_wallet.id]).once
      end

      # Usage ingested since the refresh raises the watermark, which is the whole point of the
      # lane: that customer is refreshed again even though it was refreshed a cycle ago.
      it "refreshes a caught-up customer again once its watermark has moved" do
        other_wallet
        create_other_bucket(last_ingested_at:)

        produce_other
        produce
        consumer.consume

        create_other_bucket(last_ingested_at: last_ingested_at + 1.second)
        produce_other(ingested_at: watermark + 1_000, offset: 2)

        expect { consumer.consume }
          .to have_enqueued_job(Customers::RefreshWalletJob).with(other_customer, wallet_ids: [other_wallet.id])
      end

      it "commits the messages preceding the blocked one" do
        allow(consumer).to receive(:mark_as_consumed)

        other_wallet
        create_other_bucket(last_ingested_at:)

        produce_other
        produce

        consumer.consume

        expect(consumer).to have_received(:pause).with(1, described_class::WATERMARK_PAUSE_TIMEOUT)
        expect(consumer).to have_received(:mark_as_consumed).with(consumer.messages.first)
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

        expect { consumer.consume }.not_to have_enqueued_job(Customers::RefreshWalletJob)
      end

      it "refreshes once every one of them has caught up" do
        create_bucket(subscription: second_subscription, last_ingested_at: last_ingested_at - 1.second)

        expect { consumer.consume }.to have_enqueued_job(Customers::RefreshWalletJob).once
      end
    end

    context "when the buckets stay behind for the whole attempt budget" do
      before do
        stub_const("#{described_class}::MAX_WATERMARK_ATTEMPTS", 2)

        create_bucket(last_ingested_at: last_ingested_at - 1.second)
        produce
      end

      it "stops pausing once the budget is spent" do
        3.times { consumer.consume }

        expect(consumer).to have_received(:pause).twice
      end

      # Nothing else refreshes this customer, so giving up may not mean dropping the trigger.
      it "hands the trigger to the dead letter queue" do
        3.times { consumer.consume }

        expect(dlq_messages.map { it[:payload] }).to eq([consumer.messages.first.raw_payload])
      end

      # Pausing re-delivers the same messages with their original timestamps, so the trigger
      # ages out while it is waited on. Re-judging its age there would drop it silently.
      it "hands a trigger that aged out while waiting to the dead letter queue" do
        consumer.consume

        travel(described_class::MAX_TRIGGER_AGE + 1.second)

        2.times { consumer.consume }

        expect(dlq_messages.map { it[:payload] }).to eq([consumer.messages.first.raw_payload])
      end

      # They were all re-checked on every cycle, so walking them one at a time would hold the
      # partition for one budget each.
      it "dead-letters every trigger the batch is still blocked on" do
        other_wallet
        create_other_bucket(last_ingested_at: last_ingested_at - 1.second)

        produce_other

        3.times { consumer.consume }

        expect(dlq_messages.map { it[:payload] }).to match_array(consumer.messages.map(&:raw_payload))
      end

      # `pause` seeks past the offsets between the blocked ones, so leaving them unmarked
      # would replay their refreshes after a crash or a rebalance.
      it "commits past every trigger it gave up on" do
        allow(consumer).to receive(:mark_as_consumed)

        other_wallet
        create_other_bucket(last_ingested_at: last_ingested_at - 1.second)

        produce_other

        3.times { consumer.consume }

        expect(consumer).to have_received(:mark_as_consumed).with(consumer.messages.last)
      end

      it "commits the offset it gave up on so the partition moves past it" do
        allow(consumer).to receive(:mark_as_consumed)

        3.times { consumer.consume }

        expect(consumer).to have_received(:mark_as_consumed).with(consumer.messages.first)
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

        expect { consumer.consume }
          .to have_enqueued_job(Customers::RefreshWalletJob).with(other_customer, wallet_ids: [other_wallet.id])
      end

      it "does not replay the first batch" do
        produce_other(offset: 1)

        expect { consumer.consume }
          .not_to have_enqueued_job(Customers::RefreshWalletJob).with(customer, wallet_ids: [wallet.id])
      end
    end

    context "when the batch carries several customers" do
      before do
        create_bucket(last_ingested_at:)
        other_wallet
        create_other_bucket(last_ingested_at:)
      end

      # A round-trip per customer would cost more time than the ingestion this reacts to, and
      # the whole batch is re-read on every pause cycle.
      it "reads the bucket watermarks once for the whole batch" do
        allow(RealtimeUsage::BucketWatermarkService).to receive(:call!).and_call_original

        produce
        produce_other

        consumer.consume

        expect(RealtimeUsage::BucketWatermarkService).to have_received(:call!).once
      end
    end

    # An unavailable ClickHouse cannot tell a late bucket from one that will never land, so it
    # must hold the partition rather than fail the batch or spend the trigger's budget.
    context "when the bucket watermark read fails" do
      before do
        stub_const("#{described_class}::MAX_WATERMARK_ATTEMPTS", 1)

        create_bucket(last_ingested_at:)

        allow(RealtimeUsage::BucketWatermarkService)
          .to receive(:call!).and_raise(ActiveRecord::ActiveRecordError)

        produce
      end

      it "does not enqueue the refresh" do
        expect { consumer.consume }.not_to have_enqueued_job(Customers::RefreshWalletJob)
      end

      it "waits instead of raising out of the batch" do
        consumer.consume

        expect(consumer).to have_received(:pause).with(0, described_class::WATERMARK_PAUSE_TIMEOUT)
      end

      it "keeps waiting without spending the attempt budget" do
        3.times { consumer.consume }

        expect(dlq_messages).to be_empty
      end

      # An outage, or a query that can no longer run at all, would otherwise hold the offset
      # for good: the adapter reports both as the same error.
      it "gives up once the read keeps failing past the failure budget" do
        stub_const("#{described_class}::MAX_WATERMARK_READ_FAILURES", 1)

        3.times { consumer.consume }

        expect(dlq_messages.map { it[:payload] }).to eq([consumer.messages.first.raw_payload])
      end
    end

    # The sink does not COALESCE `ingested_at`. Each of the two examples seeds the bucket the
    # other outcome would need, so neither can pass for the wrong reason.
    context "when the trigger carries no watermark" do
      it "does not refresh, even with the buckets caught up" do
        create_bucket(last_ingested_at:)
        produce(ingested_at: nil)

        expect { consumer.consume }.not_to have_enqueued_job(Customers::RefreshWalletJob)
      end

      it "does not pause, even with the buckets behind" do
        create_bucket(last_ingested_at: last_ingested_at - 1.second)
        produce(ingested_at: nil)

        consumer.consume

        expect(consumer).not_to have_received(:pause)
      end
    end

    # `Time.parse` raises on a component out of range, and reads decimal epoch milliseconds as
    # a date, so neither may reach the watermark comparison unguarded.
    context "when the trigger carries a watermark the parser cannot be trusted with" do
      it "skips a date out of range instead of failing the batch" do
        create_bucket(last_ingested_at:)
        produce(ingested_at: "2026-13-01T00:00:00Z")

        expect { consumer.consume }.not_to have_enqueued_job(Customers::RefreshWalletJob)
      end

      # Parsed as a date this lands at midnight, behind every bucket, and would refresh on
      # usage that has not landed yet.
      it "reads decimal epoch milliseconds as an epoch, not as a date" do
        create_bucket(last_ingested_at: last_ingested_at - 1.second)
        produce(ingested_at: "#{watermark}.0")

        expect { consumer.consume }.not_to have_enqueued_job(Customers::RefreshWalletJob)
      end
    end

    context "when the customer has no active wallet" do
      before do
        create_bucket(last_ingested_at:)
        customer.wallets.update_all(status: :terminated) # rubocop:disable Rails/SkipsModelValidations
      end

      it "does not enqueue the refresh" do
        produce

        expect { consumer.consume }.not_to have_enqueued_job(Customers::RefreshWalletJob)
      end
    end

    context "when the customer has a tax error" do
      before do
        create_bucket(last_ingested_at:)
        create(:error_detail, owner: customer, organization:, error_code: :tax_error)
      end

      it "does not enqueue the refresh" do
        produce

        expect { consumer.consume }.not_to have_enqueued_job(Customers::RefreshWalletJob)
      end
    end

    context "when the organization is outside the realtime usage rollout" do
      let(:organization) { create(:organization, clickhouse_events_store: true) }

      before { create_bucket(last_ingested_at:) }

      it "does not enqueue the refresh" do
        produce

        expect { consumer.consume }.not_to have_enqueued_job(Customers::RefreshWalletJob)
      end
    end
  end
end
