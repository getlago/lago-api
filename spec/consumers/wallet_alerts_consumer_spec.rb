# frozen_string_literal: true

require "rails_helper"

RSpec.describe WalletAlertsConsumer do
  subject(:consumer) { karafka.consumer_for("wallet_alerts") }

  # The test environment leaves the topic unset, so that wallet alerts go through the job everywhere
  # else and karafka.rb draws no route: the consumer gets its own, drawn once.
  before_all do
    next if Karafka::App.routes.any? { it.name == "lago_wallet_alerts_consumer" }

    # The routing DSL is evaluated in its own context, where described_class is not defined.
    consumer_class = described_class

    Karafka::App.routes.draw do
      consumer_group :lago_wallet_alerts_consumer do
        topic("wallet_alerts") { consumer consumer_class }
      end
    end
  end

  before do
    create(
      :wallet_ongoing_balance_amount_alert,
      organization:,
      wallet:,
      thresholds: [500],
      previous_value: 1000,
      direction: "decreasing"
    )

    allow(outcomes).to receive(:increment)
    allow(latency).to receive(:measure)
    karafka.produce(message.to_json)
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:wallet) { create(:wallet, organization:, customer:, balance_cents: 400, ongoing_balance_cents: 400) }
  let(:dispatched_at_ms) { ((Time.current - 2.seconds).to_f * 1000).to_i }

  let(:message) do
    {organization_id: organization.id, wallet_id: wallet.id, dispatched_at_ms:}
  end

  let(:outcomes) { Yabeda.usage_monitoring.wallet_alerts_outcomes_total }
  let(:latency) { Yabeda.usage_monitoring.wallet_alerts_latency }

  context "when premium", :premium do
    it "evaluates the wallet alerts" do
      expect { consumer.consume }.to change(organization.triggered_alerts, :count).by(1)

      triggered_alert = organization.triggered_alerts.sole
      expect(triggered_alert.wallet).to eq(wallet)
      expect(triggered_alert.current_value).to eq(400)
    end

    it "sends the alert webhook" do
      expect { consumer.consume }.to have_enqueued_job_after_commit(SendWebhookJob).with("alert.triggered", UsageMonitoring::TriggeredAlert)
    end

    it "counts the evaluation" do
      consumer.consume

      expect(outcomes).to have_received(:increment).with({outcome: "evaluated", reason: "none"}, by: 1)
    end

    it "measures the latency from the dispatch" do
      freeze_time do
        consumer.consume

        expect(latency).to have_received(:measure).with({}, Time.current.to_f - (dispatched_at_ms / 1000.0))
      end
    end

    context "with several messages for the same wallet" do
      before do
        karafka.produce(message.to_json)
        allow(UsageMonitoring::ProcessWalletAlertsService).to receive(:call!)
      end

      it "evaluates the wallet once" do
        consumer.consume

        expect(UsageMonitoring::ProcessWalletAlertsService).to have_received(:call!).once.with(wallet:)
      end

      it "measures the latency of each message" do
        consumer.consume

        expect(latency).to have_received(:measure).twice
      end
    end

    context "when the wallet does not exist" do
      let(:message) do
        {organization_id: organization.id, wallet_id: SecureRandom.uuid, dispatched_at_ms:}
      end

      it "skips it" do
        expect { consumer.consume }.not_to change(UsageMonitoring::TriggeredAlert, :count)

        expect(outcomes).to have_received(:increment).with({outcome: "skipped", reason: "wallet_not_found"}, by: 1)
      end
    end

    context "when the wallet belongs to another organization" do
      let(:message) do
        {organization_id: create(:organization).id, wallet_id: wallet.id, dispatched_at_ms:}
      end

      before { allow(UsageMonitoring::ProcessWalletAlertsService).to receive(:call!) }

      it "skips it" do
        consumer.consume

        expect(UsageMonitoring::ProcessWalletAlertsService).not_to have_received(:call!)
        expect(outcomes).to have_received(:increment).with({outcome: "skipped", reason: "wallet_not_found"}, by: 1)
      end
    end

    context "with a payload that is not valid JSON" do
      before { karafka.produce("{not json") }

      it "skips it and evaluates the others" do
        expect { consumer.consume }.to change(organization.triggered_alerts, :count).by(1)

        expect(outcomes).to have_received(:increment).with({outcome: "skipped", reason: "invalid_payload"}, by: 1)
      end
    end

    context "when the batch deadline is reached" do
      let(:other_wallet) { create(:wallet, organization:, customer:) }

      before do
        karafka.produce({organization_id: organization.id, wallet_id: other_wallet.id, dispatched_at_ms:}.to_json)
        stub_const("#{described_class}::CONSUME_DEADLINE", -1.second)
        allow(UsageMonitoring::ProcessWalletAlertsService).to receive(:call!)
      end

      it "hands the remaining wallets to the alerts job" do
        expect { consumer.consume }.to have_enqueued_job(UsageMonitoring::ProcessWalletAlertsJob).twice

        expect(UsageMonitoring::ProcessWalletAlertsService).not_to have_received(:call!)
        expect(outcomes).to have_received(:increment).with({outcome: "deferred", reason: "deadline"}, by: 1).twice
      end
    end

    context "when the batch raises" do
      before do
        allow(Wallet).to receive(:where).and_raise(ActiveRecord::ConnectionNotEstablished)
        allow(Sentry).to receive(:capture_exception)
      end

      it "raises so that Karafka retries the batch" do
        expect { consumer.consume }.to raise_error(ActiveRecord::ConnectionNotEstablished)
      end

      context "when it has been retried enough" do
        before do
          allow(consumer.coordinator.pause_tracker).to receive(:attempt).and_return(described_class::MAX_ATTEMPTS)
        end

        it "drops the batch" do
          expect { consumer.consume }.not_to raise_error

          expect(consumer.coordinator).to be_marked
          expect(Sentry).to have_received(:capture_exception).with(ActiveRecord::ConnectionNotEstablished, extra: {attempts: 3})
          expect(outcomes).to have_received(:increment).with({outcome: "failed", reason: "batch_dropped"}, by: 1)
        end
      end
    end

    context "when an evaluation raises" do
      let(:other_wallet) { create(:wallet, organization:, customer:) }

      before do
        karafka.produce({organization_id: organization.id, wallet_id: other_wallet.id, dispatched_at_ms:}.to_json)

        allow(UsageMonitoring::ProcessWalletAlertsService).to receive(:call!).and_call_original
        allow(UsageMonitoring::ProcessWalletAlertsService).to receive(:call!)
          .with(wallet:).and_raise(ActiveRecord::LockWaitTimeout)
        allow(Sentry).to receive(:capture_exception)
      end

      it "keeps consuming the batch" do
        consumer.consume

        expect(UsageMonitoring::ProcessWalletAlertsService).to have_received(:call!).with(wallet: other_wallet)
      end

      it "hands the wallet to the alerts job" do
        expect { consumer.consume }.to have_enqueued_job(UsageMonitoring::ProcessWalletAlertsJob).with(wallet)
      end

      it "reports the error" do
        consumer.consume

        expect(Sentry).to have_received(:capture_exception).with(ActiveRecord::LockWaitTimeout, extra: {wallet_id: wallet.id})
        expect(outcomes).to have_received(:increment).with({outcome: "failed", reason: "evaluation_raised"}, by: 1)
      end

      context "with an error other than a database one" do
        before do
          allow(UsageMonitoring::ProcessWalletAlertsService).to receive(:call!)
            .with(wallet:).and_raise(NoMethodError)
        end

        it "raises out of the batch" do
          expect { consumer.consume }.to raise_error(NoMethodError)
        end
      end
    end
  end

  context "when freemium" do
    it "does not evaluate the wallet alerts" do
      expect { consumer.consume }.not_to change(UsageMonitoring::TriggeredAlert, :count)

      expect(outcomes).to have_received(:increment).with({outcome: "skipped", reason: "not_premium"}, by: 1)
    end
  end
end
