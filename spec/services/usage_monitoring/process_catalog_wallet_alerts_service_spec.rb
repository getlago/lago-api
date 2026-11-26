# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::ProcessCatalogWalletAlertsService do
  subject(:result) { evaluate }

  # Lets, not let_it_be: a record created in a before_all is not committed, and the races below need a second connection
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, organization:, customer:) }
  let(:catalog_wallet) { create(:catalog_wallet, organization:, customer:, contract:, balance_cents:) }
  let(:balance_cents) { 1_500 }
  let(:previous_value) { 12_000 }
  let(:last_processed_at) { 1.hour.ago }
  let(:alert) do
    create(:catalog_wallet_alert, organization:, catalog_wallet:, alert_type: "balance", code: "low_balance", previous_value:, last_processed_at:)
  end
  let(:thresholds) do
    [
      {code: "low", value: 10_000, notify_on: %w[triggered resolved]},
      {code: "critical", value: 2_000, notify_on: %w[triggered resolved]},
      {code: "empty", value: 0}
    ]
  end

  before do
    thresholds.each { create(:catalog_wallet_alert_threshold, organization:, catalog_wallet_alert: alert, **it) }
  end

  # As the job runs it: on a wallet it loaded itself
  def evaluate
    described_class.call!(catalog_wallet: CatalogWallet.find(catalog_wallet.id))
  end

  it "sends one alert.triggered listing every line the drop from 120 to 15 crossed" do
    freeze_time do
      expect(result).to be_success

      triggered = alert.all_triggered_alerts.sole
      expect(triggered).to have_attributes(kind: "triggered", catalog_wallet:, previous_value: 12_000, current_value: 1_500, triggered_at: Time.current)
      expect(triggered.crossed_thresholds).to match_array([
        {"code" => "low", "value" => "10000.0", "recurring" => false},
        {"code" => "critical", "value" => "2000.0", "recurring" => false}
      ])
      expect(SendWebhookJob).to have_been_enqueued.once.with("alert.triggered", triggered)
      expect(alert.reload).to have_attributes(previous_value: 1_500, last_processed_at: Time.current)
    end
  end

  context "when the balance then rises to 50" do
    before do
      evaluate
      catalog_wallet.update!(balance_cents: 5_000)
    end

    it "resolves the 20 line while the 100 line stays in alarm" do
      expect(result).to be_success

      resolved = alert.all_triggered_alerts.resolved.sole
      expect(resolved).to have_attributes(
        resolution_reason: "recovered", previous_value: 1_500, current_value: 5_000, in_alarm_thresholds: ["low"], fully_resolved: false
      )
      expect(resolved.crossed_thresholds).to eq([{"code" => "critical", "value" => "2000.0", "recurring" => false}])
      expect(SendWebhookJob).to have_been_enqueued.once.with("alert.resolved", resolved)
    end
  end

  context "when the balance reaches a line exactly" do
    let(:previous_value) { 2_500 }
    let(:balance_cents) { 2_000 }

    it "triggers it, and stays silent while the balance stays there" do
      evaluate
      evaluate

      expect(alert.all_triggered_alerts.sole.crossed_thresholds).to eq([{"code" => "critical", "value" => "2000.0", "recurring" => false}])
    end
  end

  context "with a recurring step on the ongoing balance" do
    let(:catalog_wallet) do
      create(:catalog_wallet, organization:, customer:, contract:, balance_cents: 0, ongoing_balance_cents: -1_000, last_ongoing_balance_sync_at: 1.minute.ago)
    end
    let(:alert) do
      create(:catalog_wallet_alert, organization:, catalog_wallet:, alert_type: "ongoing_balance", code: "overdraft", previous_value: 0, last_processed_at:)
    end
    let(:thresholds) { [{code: "step", value: 1_000, recurring: true}] }

    it "triggers the line reached, and not again a little past it" do
      evaluate
      catalog_wallet.update!(ongoing_balance_cents: -1_100)
      evaluate

      # From the zero origin, a step of 1000 draws lines at -1000, -2000 and so on
      expect(alert.all_triggered_alerts.sole.crossed_thresholds).to eq([{"code" => "step", "value" => "-1000.0", "recurring" => true}])
    end
  end

  context "when the last evaluation is from an earlier billing period" do
    let(:previous_value) { 1_500 }
    let(:last_processed_at) { 2.months.ago }

    it "keeps watching the balance, with no window reset" do
      expect(result).to be_success

      expect(alert.all_triggered_alerts).to be_empty
      expect(alert.reload.previous_value).to eq(1_500)
    end
  end

  context "when another wallet has an alert past its lines" do
    let(:other_alert) do
      create(:catalog_wallet_alert, organization:, catalog_wallet: create(:catalog_wallet, organization:, balance_cents: 0), previous_value: 5_000, last_processed_at: 1.hour.ago)
    end

    before { create(:catalog_wallet_alert_threshold, organization:, catalog_wallet_alert: other_alert, value: 2_000) }

    it "leaves it alone" do
      result

      expect(other_alert.reload.previous_value).to eq(5_000)
      expect(other_alert.all_triggered_alerts).to be_empty
    end
  end

  context "when the alert has no baseline" do
    let(:previous_value) { nil }
    let(:last_processed_at) { nil }

    before { allow(Rails.logger).to receive(:warn) }

    it "skips it and reports the missed hook, since the wallet holds credit" do
      expect { result }.not_to change { alert.reload.attributes }

      expect(alert.all_triggered_alerts).to be_empty
      expect(Rails.logger).to have_received(:warn).with(
        "[alerts] catalog wallet alert without a baseline alert_id=#{alert.id} catalog_wallet_id=#{catalog_wallet.id}"
      )
    end

    context "when the wallet is empty" do
      let(:balance_cents) { 0 }

      it "skips it quietly, since it waits for the first credit" do
        expect { result }.not_to change { alert.reload.attributes }

        expect(alert.all_triggered_alerts).to be_empty
        expect(Rails.logger).not_to have_received(:warn)
      end
    end
  end

  (Contract::STATUSES.keys - [:active]).each do |status|
    context "when the contract is #{status}" do
      let(:contract) { create(:contract, status, organization:, customer:) }

      it "evaluates nothing" do
        expect { result }.not_to change { alert.reload.attributes }

        expect(alert.all_triggered_alerts).to be_empty
        expect(SendWebhookJob).not_to have_been_enqueued
      end
    end
  end

  context "when the wallet is terminated" do
    before { catalog_wallet.update!(terminated_at: 1.minute.ago) }

    it "evaluates nothing" do
      expect { result }.not_to change { alert.reload.attributes }

      expect(alert.all_triggered_alerts).to be_empty
      expect(SendWebhookJob).not_to have_been_enqueued
    end
  end

  context "with evaluations racing", transaction: false do
    # Keeps the block's transaction open on another connection until released
    def hold
      held = Queue.new
      release = Queue.new
      thread = Thread.new do
        ApplicationRecord.connection_pool.with_connection do
          ApplicationRecord.transaction do
            yield
            held << true
            release.pop
          end
        end
      end
      Timeout.timeout(10) { held.pop }
      [thread, release]
    end

    def in_thread(&block)
      Thread.new { ApplicationRecord.connection_pool.with_connection(&block) }
    end

    def release_once_waiting(release, count)
      Timeout.timeout(10) { sleep(0.01) until lock_waits >= count }
    ensure
      release << true
    end

    def join(*threads)
      threads.each { |thread| Timeout.timeout(10) { thread.join } }
    end

    context "when two jobs evaluate one crossing" do
      it "records it once" do
        holder, release = hold { UsageMonitoring::CatalogWalletAlert.lock.find(alert.id) }
        jobs = Array.new(2) { in_thread { evaluate } }
        release_once_waiting(release, 2)
        join(holder, *jobs)

        expect(alert.all_triggered_alerts.count).to eq(1)
        expect(alert.reload.previous_value).to eq(1_500)
      end
    end

    context "when a termination holds the contract" do
      it "waits for it and evaluates nothing" do
        termination, release = hold { Contract.lock.find(contract.id).update!(status: :terminated, terminated_at: Time.current) }
        job = in_thread { evaluate }
        release_once_waiting(release, 1)
        join(termination, job)

        expect(alert.all_triggered_alerts).to be_empty
        expect(alert.reload.previous_value).to eq(12_000)
      end
    end

    context "when the alert is deleted while the evaluation waits for it" do
      let(:ongoing_alert) do
        create(:catalog_wallet_alert, organization:, catalog_wallet:, alert_type: "ongoing_balance", code: "low_ongoing", previous_value: 12_000, last_processed_at: 1.hour.ago)
      end

      before { create(:catalog_wallet_alert_threshold, organization:, catalog_wallet_alert: ongoing_alert, value: 2_000) }

      it "skips it and evaluates the others" do
        deletion, release = hold { UsageMonitoring::CatalogWalletAlert.where(id: alert.id).delete_all }
        job = in_thread { evaluate }
        release_once_waiting(release, 1)
        join(deletion, job)

        expect(UsageMonitoring::CatalogWalletTriggeredAlert.where(catalog_wallet_alert_id: alert.id)).to be_empty
        expect(ongoing_alert.all_triggered_alerts.count).to eq(1)
      end
    end
  end
end
