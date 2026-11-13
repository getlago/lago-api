# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductEventsChargedInAdvanceConsumer do
  subject(:consumer) { karafka.consumer_for("product_events_charged_in_advance") }

  # The test environment leaves the topic unset, so karafka.rb draws no route: the consumer
  # gets its own, drawn once.
  before_all do
    next if Karafka::App.routes.any? { it.name == "lago_product_events_charged_in_advance_consumer" }

    # The routing DSL is evaluated in its own context, where described_class is not defined.
    consumer_class = described_class

    Karafka::App.routes.draw do
      consumer_group :lago_product_events_charged_in_advance_consumer do
        topic("product_events_charged_in_advance") { consumer consumer_class }
      end
    end
  end

  # The product enriched event the events processor produces, keyed by contract.
  let(:message) do
    {
      "organization_id" => SecureRandom.uuid,
      "external_contract_id" => "contract_1",
      "transaction_id" => "tx_1",
      "code" => "api_calls",
      "aggregation_type" => "sum",
      "properties" => {"amount" => "12"},
      "precise_total_amount_cents" => "0.0",
      "source" => "http_ruby",
      "value" => "12",
      "timestamp" => 1_794_231_139.499
    }
  end

  before { karafka.produce(message.to_json) }

  it "enqueues a pay in advance job for the contract, with a delay" do
    freeze_time do
      expect { consumer.consume }.to have_enqueued_job(Events::PayInAdvanceJob)
        .with(message.except("external_contract_id").merge("external_subscription_id" => "contract_1"))
        .at(Events::Stores::ClickhouseStore::CLICKHOUSE_MERGE_DELAY.from_now)
    end
  end
end
