# frozen_string_literal: true

require "rails_helper"

RSpec.describe WalletRefreshConsumer, clickhouse: {clean_before: true} do
  include_context "with realtime usage availability"

  # Not a `subject`: the partition control this consumer exercises — `pause` and
  # `mark_as_consumed` — reaches Kafka through a client the testing gem does not fake, so
  # both have to be stubbed on the consumer itself.
  let(:consumer) { karafka.consumer_for(ENV["LAGO_KAFKA_REALTIME_USAGE_TRIGGERS_TOPIC"]) }

  let(:organization) do
    create(:organization, clickhouse_events_store: true, feature_flags: ["realtime_usage"])
  end
  let(:customer) { create(:customer, organization:, awaiting_wallet_refresh: true) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:, plan:) }
  let(:billable_metric) { create(:sum_billable_metric, organization:) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }

  let(:last_ingested_at) { Time.current.beginning_of_hour }
  # What the sink actually sends: RisingWave renders a naive timestamp as epoch milliseconds.
  let(:watermark) { (last_ingested_at.to_r * 1000).to_i }

  before do
    create(:wallet, customer:, organization:)
    allow(consumer).to receive(:pause)
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

  def create_bucket(**attributes)
    create(:clickhouse_usage_bucket, organization:, customer:, subscription:, charge:, billable_metric:, **attributes)
  end

  describe "#consume" do
    context "when the buckets have caught up with the watermark" do
      before { create_bucket(last_ingested_at:) }

      it "enqueues the refresh for the customer" do
        produce

        expect { consumer.consume }.to have_enqueued_job(Customers::RefreshWalletJob).with(customer)
      end

      it "collapses every trigger of one customer into a single refresh" do
        3.times { produce }

        expect { consumer.consume }.to have_enqueued_job(Customers::RefreshWalletJob).with(customer).once
      end

      it "tolerates a watermark sent as a timestamp string" do
        produce(ingested_at: last_ingested_at.utc.iso8601(3))

        expect { consumer.consume }.to have_enqueued_job(Customers::RefreshWalletJob).with(customer)
      end

      it "does not pause the partition" do
        produce
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

      it "commits the messages preceding the blocked one" do
        allow(consumer).to receive(:mark_as_consumed)

        other_customer = create(:customer, organization:, awaiting_wallet_refresh: true)
        create(:wallet, customer: other_customer, organization:)
        other_subscription = create(:subscription, organization:, customer: other_customer, plan:)

        create(
          :clickhouse_usage_bucket,
          organization:, customer: other_customer, subscription: other_subscription,
          charge:, billable_metric:, last_ingested_at:
        )

        produce(customer_id: other_customer.id, subscription_id: other_subscription.id)
        produce

        consumer.consume

        expect(consumer).to have_received(:pause).with(1, described_class::WATERMARK_PAUSE_TIMEOUT)
        expect(consumer).to have_received(:mark_as_consumed).with(consumer.messages.first)
      end
    end

    # Karafka keeps the consumer instance alive across batches, so per-batch state that
    # outlived a `consume` would replay the first batch instead of the one just delivered.
    context "when the consumer instance is reused across batches" do
      let(:other_customer) { create(:customer, organization:, awaiting_wallet_refresh: true) }
      let(:other_subscription) { create(:subscription, organization:, customer: other_customer, plan:) }

      before do
        create_bucket(last_ingested_at:)
        create(:wallet, customer: other_customer, organization:)
        create(
          :clickhouse_usage_bucket,
          organization:, customer: other_customer, subscription: other_subscription,
          charge:, billable_metric:, last_ingested_at:
        )

        produce
        consumer.consume
        _karafka_consumer_messages.clear
      end

      it "refreshes the customer carried by the second batch" do
        produce(customer_id: other_customer.id, subscription_id: other_subscription.id, offset: 1)

        expect { consumer.consume }
          .to have_enqueued_job(Customers::RefreshWalletJob).with(other_customer)
      end

      it "does not replay the first batch" do
        produce(customer_id: other_customer.id, subscription_id: other_subscription.id, offset: 1)

        expect { consumer.consume }
          .not_to have_enqueued_job(Customers::RefreshWalletJob).with(customer)
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

    context "when the customer is not awaiting a refresh" do
      before do
        create_bucket(last_ingested_at:)
        customer.update!(awaiting_wallet_refresh: false)
      end

      it "does not enqueue the refresh" do
        produce

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
