# frozen_string_literal: true

RSpec.describe Utils::KafkaProducer do
  describe ".produce_async" do
    subject(:produce_async) { described_class.produce_async(topic: "test_topic", key: "test_key", payload: "test_payload") }

    it "produces the message on kafka and returns true" do
      expect(produce_async).to be(true)
      expect(karafka.produced_messages).to eq([
        {
          topic: "test_topic",
          key: "test_key",
          payload: "test_payload"
        }
      ])
    end

    [
      {exception: WaterDrop::Errors::ProduceError, message: "#<Rdkafka::RdkafkaError: Local: Unknown topic (unknown_topic)>", level: :error},
      {exception: WaterDrop::Errors::MessageInvalidError, message: "Message is too large", level: :error}
    ].each do |error_context|
      exception = error_context[:exception]
      message = error_context[:message]
      level = error_context[:level]

      context "when producer raises #{exception}" do
        before do
          allow(Karafka.producer).to receive(:produce_async).and_raise(exception.new(message))
        end

        context "when sentry is configured", :sentry do
          it "captures the exception with the #{level} level and returns false" do
            expect(produce_async).to be(false)
            expect(sentry_events).to include_sentry_event(exception: exception, message: message)
            expect(sentry_events.last.level).to eq(level)
          end
        end

        context "when sentry is not configured" do
          it "re-raises the error" do
            expect { produce_async }.to raise_error(exception, message)
            expect(sentry_events).to be_empty
          end
        end
      end
    end

    context "with invalid_message_level", :sentry do
      subject(:produce_async) do
        described_class.produce_async(topic: "test_topic", key: "test_key", payload: "test_payload", invalid_message_level: :warning)
      end

      context "when producer raises WaterDrop::Errors::MessageInvalidError" do
        before do
          allow(Karafka.producer).to receive(:produce_async).and_raise(WaterDrop::Errors::MessageInvalidError.new("Message is too large"))
        end

        it "captures the exception with the given level" do
          expect(produce_async).to be(false)
          expect(sentry_events.last.level).to eq(:warning)
        end
      end

      context "when producer raises WaterDrop::Errors::ProduceError" do
        before do
          allow(Karafka.producer).to receive(:produce_async).and_raise(WaterDrop::Errors::ProduceError.new("Unknown topic"))
        end

        it "captures the exception with the error level" do
          expect(produce_async).to be(false)
          expect(sentry_events.last.level).to eq(:error)
        end
      end
    end
  end
end
