# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::NotifyFailureService, type: :service do
  let(:webhook) { create(:webhook, status: :failed) }
  let(:service) { described_class.new(webhook: webhook) }
  let(:cache_key) { "webhook_failure_notification:#{webhook.organization_id}" }

  describe "#call" do
    subject(:service_call) { service.call }

    before do
      allow(Rails.cache).to receive(:read).with(cache_key).and_return(nil)
      allow(Rails.cache).to receive(:write)
      allow(mailer_spy = instance_double(WebhookMailer))
        .to receive(:failure_notification).and_return(double(deliver_later: true)) # rubocop:disable RSpec/VerifiedDoubles
      allow(WebhookMailer).to receive(:with).with(webhook: webhook).and_return(mailer_spy)
      allow_any_instance_of(described_class).to receive(:should_notify?).and_return(should_notify) # rubocop:disable RSpec/AnyInstance
    end

    context "when should notify" do
      let(:should_notify) { true }

      it "sends a failure notification email and writes the notification time to cache" do
        freeze_time do
          result = service_call
          expect(result).to be_success
          expect(WebhookMailer.with(webhook:).failure_notification).to have_received(:deliver_later)
          expect(Rails.cache).to have_received(:write).with(cache_key, Time.current, expires_in: 1.hour)
        end
      end
    end

    context "when should not notify" do
      let(:should_notify) { false }

      it "does not send a notification email" do
        result = service_call
        expect(result).to be_success
        expect(WebhookMailer).not_to have_received(:with)
        expect(Rails.cache).not_to have_received(:write)
      end
    end
  end

  describe "#should_notify?" do
    subject(:should_notify) { service.send(:should_notify?) }

    context "when no previous notification exists" do
      before do
        allow(Rails.cache).to receive(:read).with(cache_key).and_return(nil)
      end

      it { is_expected.to be true }
    end

    context "when previous notification is less than an hour old" do
      before do
        allow(Rails.cache).to receive(:read).with(cache_key).and_return(30.minutes.ago)
      end

      it { is_expected.to be false }
    end

    context "when previous notification is exactly an hour old" do
      before do
        allow(Rails.cache).to receive(:read).with(cache_key).and_return(1.hour.ago)
      end

      it { is_expected.to be true }
    end

    context "when previous notification is more than an hour old" do
      before do
        allow(Rails.cache).to receive(:read).with(cache_key).and_return(2.hours.ago)
      end

      it { is_expected.to be true }
    end
  end

  describe "#cache_key" do
    subject(:cache_key_value) { service.send(:cache_key) }

    it "returns the correct cache key format" do
      expect(cache_key_value).to eq("webhook_failure_notification:#{webhook.organization_id}")
    end
  end
end
