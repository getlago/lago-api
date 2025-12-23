# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::CreateBatchService do
  subject(:create_batch_service) do
    described_class.new(
      organization:,
      events_params:,
      timestamp: creation_timestamp,
      metadata:
    )
  end

  let(:organization) { create(:organization) }
  let(:timestamp) { Time.current.to_f }
  let(:code) { "sum_agg" }
  let(:metadata) { {} }
  let(:creation_timestamp) { Time.current.to_f }
  let(:precise_total_amount_cents) { "123.34" }
  let(:external_subscription_id) { SecureRandom.uuid }
  let(:events_params) { build_params }

  def build_params(count: 100, &block)
    events = []
    count.times do |i|
      event = {
        external_customer_id: SecureRandom.uuid,
        external_subscription_id:,
        code:,
        transaction_id: SecureRandom.uuid,
        precise_total_amount_cents:,
        properties: {foo: "bar"},
        timestamp:
      }
      yield(event, i) if block_given?

      events << event
    end

    {events:}
  end

  def test_validation_failure(expected_errors)
    result = nil

    expect { result = create_batch_service.call }.not_to change(Event, :count)

    expect(result).not_to be_success
    expect(result.error).to be_a(BaseService::ValidationFailure)
    expect(result.error.messages).to eq expected_errors
  end

  describe ".call" do
    it "creates all events" do
      result = nil

      expect { result = create_batch_service.call }.to change(Event, :count).by(100)

      expect(result).to be_success
    end

    it "enqueues a post processing job" do
      expect { create_batch_service.call }.to have_enqueued_job(Events::PostProcessJob).exactly(100)
    end

    context "when no events are provided" do
      let(:events_params) { build_params(count: 0) }

      it "returns a no_events error" do
        test_validation_failure({events: ["no_events"]})
      end
    end

    context "when events count is too big" do
      let(:events_params) { build_params(count: 101) }

      it "returns a too big error" do
        test_validation_failure({events: ["too_many_events"]})
      end
    end

    context "with at least one invalid event" do
      context "with duplicate transaction_id" do
        let(:duplicate_transaction_id) { SecureRandom.uuid }
        let(:events_params) { build_params(count: 2) { |event, index| event[:transaction_id] = duplicate_transaction_id } }

        it "returns a duplicate transaction_id error" do
          test_validation_failure({1 => {transaction_id: ["value_already_exist"]}})
        end
      end

      context "with already existing event", transaction: false do
        let(:existing_event) do
          create(:event, organization:, transaction_id: "123456", external_subscription_id:)
        end
        let(:events_params) do
          build_params(count: 2) do |event, index|
            event[:transaction_id] = existing_event.transaction_id if index == 1
          end
        end

        before { existing_event }

        it "returns an error" do
          test_validation_failure({1 => {transaction_id: ["value_already_exist"]}})
        end
      end
    end

    context "when timestamp is not present in the payload" do
      let(:events_params) { build_params(count: 1) { it.delete(:timestamp) } }

      it "creates an event by setting the timestamp to the current datetime" do
        result = create_batch_service.call

        expect(result).to be_success
        expect(result.events.first.timestamp).to eq(Time.zone.at(creation_timestamp))
      end
    end

    context "when timestamp is given as string" do
      let(:timestamp) { Time.current.to_f.to_s }
      let(:events_params) { build_params(count: 1) { |event| event[:timestamp] = timestamp } }

      it "creates an event by setting timestamp" do
        result = create_batch_service.call

        expect(result).to be_success
        expect(result.events.first.timestamp).to eq(Time.zone.at(timestamp.to_f))
      end
    end

    context "when timestamp is in a wrong format" do
      let(:timestamp) { Time.current.to_s }
      let(:events_params) { build_params(count: 1) { |event| event[:timestamp] = timestamp } }

      it "returns an error" do
        test_validation_failure({0 => {timestamp: ["invalid_format"]}})
      end
    end

    context "with an expression configured on the billable metric" do
      let(:billable_metric) { create(:billable_metric, code:, organization:, field_name: "result", expression: "concat(event.properties.foo, '-bar')") }

      before do
        billable_metric
      end

      it "creates an event and updates the field name with the result of the expression" do
        result = create_batch_service.call

        expect(result).to be_success
        result.events.each { |event| expect(event.properties["result"]).to eq("bar-bar") }
      end

      context "when not all the event properties are not provided" do
        let(:events_params) { build_params(count: 1) { |event| event[:properties] = {} } }

        it "returns a failure when the expression fails to evaluate" do
          test_validation_failure({0 => "expression_evaluation_failed: Variable: foo not found"})
        end
      end
    end

    context "when timestamp is sent with decimal precision" do
      let(:timestamp) { DateTime.parse("2023-09-04T15:45:12.344Z").to_f }
      let(:events_params) { build_params(count: 1) { |event| event[:timestamp] = timestamp } }

      it "creates an event by keeping the millisecond precision" do
        result = create_batch_service.call

        expect(result).to be_success
        expect(result.events.first.timestamp.iso8601(3)).to eq("2023-09-04T15:45:12.344Z")
      end
    end

    context "when kafka is configured" do
      let(:karafka_producer) { instance_double(WaterDrop::Producer) }

      before do
        ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"] = "kafka"
        ENV["LAGO_KAFKA_RAW_EVENTS_TOPIC"] = "raw_events"
      end

      after do
        ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"] = nil
        ENV["LAGO_KAFKA_RAW_EVENTS_TOPIC"] = nil
      end

      it "produces the event on kafka" do
        allow(Karafka).to receive(:producer).and_return(karafka_producer)
        allow(karafka_producer).to receive(:produce_async)

        create_batch_service.call

        expect(karafka_producer).to have_received(:produce_async).exactly(100)
      end
    end

    context "when clickhouse is enabled on the organization" do
      let(:organization) { create(:organization, clickhouse_events_store: true) }

      it "does not store the event in postgres" do
        result = nil

        expect { result = create_batch_service.call }.not_to change(Event, :count)
        expect(result).to be_success
      end

      it "does not enqueues a post processing job" do
        expect { create_batch_service.call }.not_to have_enqueued_job(Events::PostProcessJob)
      end

      context "when kafka is configured" do
        let(:karafka_producer) { instance_double(WaterDrop::Producer) }

        before do
          ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"] = "kafka"
          ENV["LAGO_KAFKA_RAW_EVENTS_TOPIC"] = "raw_events"
        end

        after do
          ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"] = nil
          ENV["LAGO_KAFKA_RAW_EVENTS_TOPIC"] = nil
        end

        it "produces the event on kafka" do
          allow(Karafka).to receive(:producer).and_return(karafka_producer)
          allow(karafka_producer).to receive(:produce_async)

          create_batch_service.call

          expect(karafka_producer).to have_received(:produce_async).exactly(100)
        end
      end
    end
  end
end
