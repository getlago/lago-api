# frozen_string_literal: true

require "rails_helper"

RSpec.describe RealtimeUsage::WalletRefreshTriggersService do
  subject(:service) { described_class.call(messages:, paused_offset:) }

  let(:messages) { [build_message] }
  let(:paused_offset) { nil }

  let(:organization_id) { SecureRandom.uuid }
  let(:customer_id) { SecureRandom.uuid }
  let(:subscription_id) { SecureRandom.uuid }
  let(:other_subscription_id) { SecureRandom.uuid }

  let(:last_ingested_at) { Time.zone.parse("2026-09-03T10:15:00.250Z") }
  let(:watermark_ms) { (last_ingested_at.to_r * 1000).to_i }

  def build_message(offset: 0, timestamp: Time.current, **payload)
    defaults = {
      "organization_id" => organization_id,
      "customer_id" => customer_id,
      "subscription_id" => subscription_id,
      "last_ingested_at" => watermark_ms
    }

    instance_double(
      Karafka::Messages::Message,
      offset:,
      timestamp:,
      payload: defaults.merge(payload.transform_keys(&:to_s))
    )
  end

  describe "#call" do
    it "builds one trigger per customer, keyed by customer id" do
      expect(service.triggers).to eq(
        customer_id => {
          organization_id:,
          customer_id:,
          watermarks_ms: {subscription_id => watermark_ms},
          offset: 0
        }
      )
    end

    it "keeps the highest watermark of a subscription the batch carries twice" do
      messages = [build_message, build_message(offset: 1, last_ingested_at: watermark_ms + 1_000)]

      result = described_class.call(messages:, paused_offset: nil)

      expect(result.triggers[customer_id][:watermarks_ms]).to eq(subscription_id => watermark_ms + 1_000)
    end

    # The refresh reads every subscription of the customer, so none of them may be dropped.
    it "keeps every subscription of one customer" do
      messages = [
        build_message,
        build_message(offset: 1, subscription_id: other_subscription_id, last_ingested_at: watermark_ms - 1_000)
      ]

      result = described_class.call(messages:, paused_offset: nil)

      expect(result.triggers[customer_id][:watermarks_ms])
        .to eq(subscription_id => watermark_ms, other_subscription_id => watermark_ms - 1_000)
    end

    # Where the partition has to resume when the customer turns out to be blocked.
    it "keeps the offset of the customer's first message" do
      messages = [build_message(offset: 3), build_message(offset: 4)]

      result = described_class.call(messages:, paused_offset: nil)

      expect(result.triggers[customer_id][:offset]).to eq(3)
    end

    it "skips a trigger missing an id" do
      messages = [build_message(subscription_id: nil)]

      result = described_class.call(messages:, paused_offset: nil)

      expect(result.triggers).to be_empty
    end

    it "skips a trigger carrying no watermark" do
      messages = [build_message(last_ingested_at: nil)]

      result = described_class.call(messages:, paused_offset: nil)

      expect(result.triggers).to be_empty
    end

    context "when the trigger is older than the maximum age" do
      let(:messages) { [build_message(timestamp: described_class::MAX_TRIGGER_AGE.ago - 1.second)] }

      it "leaves it to the clock sweep and counts it" do
        expect(service.triggers).to be_empty
        expect(service.stale_count).to eq(1)
      end

      # A pause re-delivers the same messages with their original timestamps, so re-judging
      # them would age out the very trigger the pause is waiting for.
      context "when the partition is paused at that offset" do
        let(:paused_offset) { 0 }

        it "does not judge its age again" do
          expect(service.triggers).not_to be_empty
          expect(service.stale_count).to be_zero
        end
      end
    end

    it "keeps a trigger produced inside the age window" do
      messages = [build_message(timestamp: (described_class::MAX_TRIGGER_AGE - 5.seconds).ago)]

      result = described_class.call(messages:, paused_offset: nil)

      expect(result.triggers).not_to be_empty
    end

    context "when the watermark is not an integer" do
      it "tolerates a rendered timestamp" do
        messages = [build_message(last_ingested_at: last_ingested_at.utc.iso8601(3))]

        result = described_class.call(messages:, paused_offset: nil)

        expect(result.triggers[customer_id][:watermarks_ms]).to eq(subscription_id => watermark_ms)
      end

      # Parsed as a date this lands at midnight, behind every bucket, and would refresh on
      # usage that has not landed yet.
      it "reads decimal epoch milliseconds as an epoch, not as a date" do
        messages = [build_message(last_ingested_at: "#{watermark_ms}.0")]

        result = described_class.call(messages:, paused_offset: nil)

        expect(result.triggers[customer_id][:watermarks_ms]).to eq(subscription_id => watermark_ms)
      end

      it "skips a date out of range instead of raising" do
        messages = [build_message(last_ingested_at: "2026-13-01T00:00:00Z")]

        result = described_class.call(messages:, paused_offset: nil)

        expect(result.triggers).to be_empty
      end
    end
  end
end
