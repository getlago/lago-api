# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEngineMigrationEventsConsumer, :capture_kafka_messages do
  subject(:consumer) { karafka.consumer_for("raw_events") }

  # The topic is unset in tests, so karafka.rb draws no route.
  before_all do
    next if Karafka::App.routes.any? { it.name == "lago_billing_engine_migration_events_consumer" }

    # The routing DSL is evaluated in its own context, where described_class is not defined.
    consumer_class = described_class

    Karafka::App.routes.draw do
      consumer_group :lago_billing_engine_migration_events_consumer do
        topic("raw_events") { consumer consumer_class }
      end
    end
  end

  let_it_be(:organization) { create(:organization) }
  let_it_be(:shadow_organization) { create(:shadow_organization) }
  let_it_be(:other_organization) { create(:organization) }
  let_it_be(:customer) { create(:customer, organization:) }
  let_it_be(:plan) { create(:plan, organization:, code: "legacy") }
  let_it_be(:subscription) { create(:subscription, customer:, plan:, external_id: "sub-mapped") }

  let(:events_copy_source) { "raw_topic" }
  let(:status) { "shadowing" }

  let(:outcomes) { Yabeda.billing_engine_migrations.events_copy_total }
  let(:failures) { Yabeda.billing_engine_migrations.events_copy_failures_total }
  let(:lag) { Yabeda.billing_engine_migrations.events_copy_lag }

  def raw_event(organization_id, transaction_id, external_subscription_id: "sub-mapped")
    {
      organization_id:,
      external_subscription_id:,
      transaction_id:,
      code: "api_calls",
      timestamp: "1763900000.123",
      precise_total_amount_cents: "0.0",
      properties: {}
    }.to_json
  end

  before do
    stub_const("ENV", ENV.to_h.merge("LAGO_KAFKA_BOOTSTRAP_SERVERS" => "kafka", "LAGO_KAFKA_PRODUCT_RAW_EVENTS_TOPIC" => "product_events_raw"))

    create(
      :billing_engine_migration,
      organization:,
      shadow_organization:,
      status:,
      plan_mapping: {"legacy" => "catalog"},
      events_copy_source:
    )

    allow(outcomes).to receive(:increment)
    allow(failures).to receive(:increment)
    allow(lag).to receive(:measure)

    karafka.produce(raw_event(organization.id, "tr-1"))
    karafka.produce(raw_event(organization.id, "tr-2", external_subscription_id: "sub-unmapped"))
    karafka.produce(raw_event(other_organization.id, "tr-3"))
    karafka.produce(nil)
  end

  it "copies the events of mapped subscriptions to the shadow organization" do
    consumer.consume

    expect(kafka_messages.map { JSON.parse(it[:payload]).values_at("organization_id", "transaction_id") })
      .to eq([[shadow_organization.id, "tr-1"]])
    expect(outcomes).to have_received(:increment).with({outcome: "copied"}, by: 1)
    expect(outcomes).to have_received(:increment).with({outcome: "unmapped"}, by: 1)
    expect(outcomes).not_to have_received(:increment).with({outcome: "invalid"}, by: anything)
  end

  it "reports the age of the batch" do
    consumer.consume

    expect(lag).to have_received(:measure).with({}, kind_of(Numeric))
  end

  context "when the migration copies its events through the API" do
    let(:events_copy_source) { "api" }

    it "copies nothing" do
      consumer.consume

      expect(kafka_messages).to be_empty
      expect(outcomes).not_to have_received(:increment)
      expect(lag).to have_received(:measure)
    end
  end

  context "when the migration is paused" do
    let(:status) { "paused" }

    it "copies nothing" do
      consumer.consume

      expect(kafka_messages).to be_empty
    end
  end

  context "when the copy fails" do
    before { allow(karafka_producer).to receive(:produce_many_sync).and_raise(WaterDrop::Errors::ProduceManyError.new([], "boom")) }

    it "reports the failure and raises so the batch is retried" do
      expect { consumer.consume }.to raise_error(WaterDrop::Errors::ProduceManyError)

      expect(failures).to have_received(:increment).with({})
      expect(outcomes).not_to have_received(:increment)
    end
  end
end
