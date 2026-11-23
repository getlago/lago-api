# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::CatalogWalletAlerts::BaselineService do
  subject(:result) { described_class.call(catalog_wallet: CatalogWallet.find(catalog_wallet.id)) }

  # A let, not a let_it_be: a record created in a before_all is not committed, and the race below needs a second connection
  let(:organization) { create(:organization) }
  let(:catalog_wallet) { create(:catalog_wallet, organization:, balance_cents: 1_500, ongoing_balance_cents: 1_200) }
  let(:alert) { create(:catalog_wallet_alert, organization:, catalog_wallet:, alert_type: "balance", code: "low_balance") }

  before do
    create(:catalog_wallet_alert_threshold, organization:, catalog_wallet_alert: alert, code: "warning", value: 2_000, notify_on: %w[triggered resolved])
    create(:catalog_wallet_alert_threshold, organization:, catalog_wallet_alert: alert, code: "silent", value: 1_800)
    create(:catalog_wallet_alert_threshold, organization:, catalog_wallet_alert: alert, code: "empty", value: 0, notify_on: %w[triggered resolved])
  end

  it "takes the balance as the baseline and seeds the opted-in lines already past, sending nothing" do
    freeze_time do
      expect { result }.not_to have_enqueued_job(SendWebhookJob)

      expect(result.alerts).to eq([alert])
      expect(alert.reload).to have_attributes(previous_value: 1_500, last_processed_at: Time.current)
      # 2000 is above the balance of 1500 and opted in; 1800 is above it too, but only announces crossings
      seeded = alert.all_triggered_alerts.sole
      expect(seeded).to have_attributes(kind: "seeded", catalog_wallet:, current_value: 1_500, previous_value: 1_500)
      expect(seeded.crossed_thresholds).to eq([{"code" => "warning", "value" => "2000.0", "recurring" => false}])
    end
  end

  context "with an ongoing balance alert" do
    let(:alert) { create(:catalog_wallet_alert, organization:, catalog_wallet:, alert_type: "ongoing_balance", code: "low_ongoing_balance") }

    it "takes the ongoing balance as the baseline" do
      expect(result.alerts).to eq([alert])
      expect(alert.reload.previous_value).to eq(1_200)
      expect(alert.all_triggered_alerts.sole.crossed_thresholds.pluck("code")).to eq(["warning"])
    end
  end

  context "when the wallet is empty" do
    let(:catalog_wallet) { create(:catalog_wallet, organization:, balance_cents: 0, ongoing_balance_cents: 0) }
    let(:ongoing_alert) { create(:catalog_wallet_alert, organization:, catalog_wallet:, alert_type: "ongoing_balance", code: "low_ongoing_balance") }

    before do
      create(:catalog_wallet_alert_threshold, organization:, catalog_wallet_alert: ongoing_alert, code: "empty", value: 0, notify_on: %w[triggered resolved])
    end

    it "leaves the balance alert waiting for money" do
      result

      expect(alert.reload).to have_attributes(previous_value: nil, last_processed_at: nil)
      expect(alert.all_triggered_alerts).to be_empty
    end

    it "starts the ongoing balance alert at 0 and seeds nothing, though its line at 0 is reached" do
      expect(result.alerts).to eq([ongoing_alert])
      expect(ongoing_alert.reload.previous_value).to eq(0)
      expect(ongoing_alert.all_triggered_alerts).to be_empty
    end

    context "when usage already took the ongoing balance below 0" do
      let(:catalog_wallet) { create(:catalog_wallet, organization:, balance_cents: 0, ongoing_balance_cents: -300) }

      it "starts the ongoing balance alert at that value and seeds nothing" do
        expect(result.alerts).to eq([ongoing_alert])
        expect(ongoing_alert.reload.previous_value).to eq(-300)
        expect(ongoing_alert.all_triggered_alerts).to be_empty
      end
    end
  end

  context "when the alert already has a baseline" do
    let(:alert) { create(:catalog_wallet_alert, organization:, catalog_wallet:, alert_type: "balance", previous_value: 900, last_processed_at: 1.day.ago) }

    it "leaves it as it is" do
      expect { result }.not_to change { alert.reload.attributes }
      expect(result.alerts).to be_empty
      expect(alert.all_triggered_alerts).to be_empty
    end
  end

  context "when another wallet has an alert without a baseline" do
    let(:other_alert) { create(:catalog_wallet_alert, organization:, catalog_wallet: create(:catalog_wallet, organization:, balance_cents: 1_000)) }

    before { other_alert }

    it "leaves it waiting" do
      result

      expect(other_alert.reload.previous_value).to be_nil
    end
  end

  context "when a balance change is in flight", transaction: false do
    it "waits for it and takes the balance it leaves" do
      locked = Queue.new
      release = Queue.new

      writer = Thread.new do
        ApplicationRecord.connection_pool.with_connection do
          ApplicationRecord.transaction do
            CatalogWallet.find(catalog_wallet.id).update!(balance_cents: 3_000)
            locked << true
            release.pop
          end
        end
      end
      Timeout.timeout(10) { locked.pop }

      baseline = Thread.new do
        ApplicationRecord.connection_pool.with_connection { described_class.call(catalog_wallet: CatalogWallet.find(catalog_wallet.id)) }
      end
      begin
        Timeout.timeout(10) { sleep(0.01) until lock_waits.positive? }
      ensure
        release << true
      end
      Timeout.timeout(10) { writer.join }
      Timeout.timeout(10) { baseline.join }

      expect(alert.reload.previous_value).to eq(3_000)
    end
  end

  def lock_waits
    ApplicationRecord.connection.select_value(
      "SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND wait_event_type = 'Lock'"
    )
  end
end
