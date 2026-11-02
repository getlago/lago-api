# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::AnnounceMissedThresholdsService do
  subject(:result) { travel_to(now) { described_class.call(from:, to:, organization_id:, dry_run:) } }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:customer) { create(:customer, organization:) }
  let_it_be(:plan) { create(:plan, organization:, interval: :monthly) }
  let_it_be(:subscription) do
    create(:subscription, :calendar, organization:, customer:, plan:, started_at: Time.zone.parse("2026-01-01T00:00:00Z"))
  end
  let_it_be(:billable_metric) { create(:billable_metric, organization:) }

  # The current calendar period of the subscription starts on 2026-03-01
  let(:now) { Time.zone.parse("2026-03-15T12:00:00Z") }
  let(:from) { Time.zone.parse("2026-02-15T00:00:00Z") }
  let(:to) { now }
  let(:organization_id) { organization.id }
  let(:dry_run) { false }

  let(:alert_factory) { :billable_metric_current_usage_units_alert }
  let(:alert_created_at) { Time.zone.parse("2026-03-10T09:00:00Z") }
  let(:alert_subscription) { subscription }
  let(:alert_metric) { billable_metric }
  let(:thresholds) { [50, 100, 200] }
  let(:recurring_threshold) { nil }
  let(:previous_value) { 150 }
  let(:last_processed_at) { Time.zone.parse("2026-03-15T11:00:00Z") }
  let(:alert) do
    # Created at its own time, so its thresholds carry the creation timestamp as they do in production
    travel_to(alert_created_at) do
      create(
        alert_factory,
        organization:,
        subscription_external_id: alert_subscription.external_id,
        billable_metric: alert_metric,
        code: "baseline",
        thresholds:,
        recurring_threshold:,
        previous_value:,
        last_processed_at:
      )
    end
  end

  before { alert }

  def entry(status:, reason: nil, thresholds: [], alert: self.alert)
    {
      alert_id: alert.id,
      organization_id: alert.organization_id,
      alert_type: alert.alert_type,
      alert_code: alert.code,
      status:,
      reason:,
      previous_value: alert.previous_value,
      thresholds:
    }
  end

  context "when the alert passed some thresholds before its creation baseline" do
    let(:seeded) do
      create(
        :triggered_alert,
        alert:,
        organization:,
        subscription:,
        kind: :seeded,
        current_value: 150,
        previous_value: 0,
        crossed_thresholds: [{code: "warn50", value: "50.0", recurring: false}]
      )
    end

    before { seeded }

    it "records one triggered row from 0 and sends alert.triggered after commit" do
      expect { result }.to have_enqueued_job_after_commit(SendWebhookJob)
        .with("alert.triggered", instance_of(UsageMonitoring::TriggeredAlert))

      expect(result).to be_success
      expect(result.report).to eq([entry(status: :announced, thresholds: [50, 100])])

      triggered_alert = alert.triggered_alerts.sole
      expect(SendWebhookJob).to have_been_enqueued.with("alert.triggered", triggered_alert)
      expect(triggered_alert).to have_attributes(
        organization_id: organization.id,
        subscription_id: subscription.id,
        wallet_id: nil,
        kind: "triggered",
        current_value: 150,
        previous_value: 0,
        triggered_at: now
      )

      expect(::V1::UsageMonitoring::TriggeredAlertSerializer.new(triggered_alert, root_name: "triggered_alert").serialize).to eq({
        lago_id: triggered_alert.id,
        lago_organization_id: organization.id,
        lago_alert_id: alert.id,
        lago_subscription_id: subscription.id,
        external_subscription_id: subscription.external_id,
        lago_wallet_id: nil,
        external_customer_id: customer.external_id,
        billable_metric_code: billable_metric.code,
        alert_name: "General Alert",
        alert_code: "baseline",
        alert_type: "billable_metric_current_usage_units",
        current_value: BigDecimal("150"),
        previous_value: BigDecimal("0"),
        crossed_thresholds: [
          {"code" => "warn50", "value" => "50.0", "recurring" => false},
          {"code" => "warn100", "value" => "100.0", "recurring" => false}
        ],
        triggered_at: now.iso8601,
        subscription_external_id: subscription.external_id,
        customer_external_id: customer.external_id
      })
    end

    it "leaves the alert and its seeded rows unchanged" do
      expect { result }.not_to change { alert.reload.attributes }
      expect(seeded.reload).to have_attributes(kind: "seeded", current_value: 150, updated_at: seeded.updated_at)
      expect(alert.all_triggered_alerts.seeded.sole).to eq(seeded)
    end

    context "when it runs as a dry run" do
      subject(:result) { travel_to(now) { described_class.call(from:, to:, organization_id:) } }

      it "reports what it would announce and writes nothing" do
        expect(result.report).to eq([entry(status: :would_announce, thresholds: [50, 100])])
        expect(alert.triggered_alerts).to be_empty
        expect(SendWebhookJob).not_to have_been_enqueued
      end
    end
  end

  context "with a recurring threshold below the value" do
    let(:thresholds) { [50, 100] }
    let(:recurring_threshold) { 100 }
    let(:previous_value) { 350 }

    it "announces the lines the first evaluation from 0 would" do
      # one-time 50 and 100, then recurring lines every 100 past the last one-time line: 200 and 300 (400 > 350)
      expect(result.report).to eq([entry(status: :announced, thresholds: [50, 100, 200, 300])])
      expect(alert.triggered_alerts.sole.crossed_thresholds).to eq([
        {"code" => "warn50", "value" => "50.0", "recurring" => false},
        {"code" => "warn100", "value" => "100.0", "recurring" => false},
        {"code" => "rec", "value" => "200.0", "recurring" => true},
        {"code" => "rec", "value" => "300.0", "recurring" => true}
      ])
    end
  end

  context "when the value is below every threshold" do
    let(:previous_value) { 40 }

    it "skips the alert" do
      expect(result.report).to eq([entry(status: :skipped, reason: :below_thresholds)])
      expect(alert.all_triggered_alerts).to be_empty
      expect(SendWebhookJob).not_to have_been_enqueued
    end
  end

  context "when a triggered row already covers the missed lines" do
    before do
      create(:triggered_alert, alert:, organization:, subscription:, current_value: 120, previous_value: 0)
    end

    it "skips the alert" do
      expect(result.report).to eq([entry(status: :skipped, reason: :already_announced)])
      expect(alert.triggered_alerts.count).to eq(1)
      expect(SendWebhookJob).not_to have_been_enqueued
    end
  end

  context "when a triggered row covers only the lower missed lines" do
    before do
      create(:triggered_alert, alert:, organization:, subscription:, current_value: 60, previous_value: 0)
    end

    it "announces the lines above it" do
      expect(result.report).to eq([entry(status: :announced, thresholds: [100])])
      expect(alert.triggered_alerts.order(:current_value).last.crossed_thresholds)
        .to eq([{"code" => "warn100", "value" => "100.0", "recurring" => false}])
    end
  end

  context "when the task runs a second time" do
    before { travel_to(now) { described_class.call(from:, to:, organization_id:, dry_run: false) } }

    it "skips the alert it already announced" do
      expect(result.report).to eq([entry(status: :skipped, reason: :already_announced)])
      expect(alert.triggered_alerts.count).to eq(1)
    end
  end

  context "when the alert was never evaluated" do
    let(:last_processed_at) { nil }

    it "skips the alert" do
      expect(result.report).to eq([entry(status: :skipped, reason: :never_evaluated)])
      expect(alert.all_triggered_alerts).to be_empty
    end
  end

  context "when the subscription is not active" do
    let(:alert_subscription) do
      create(:subscription, :terminated, organization:, customer:, plan:, external_id: "terminated-sub")
    end

    it "skips the alert" do
      expect(result.report).to eq([entry(status: :skipped, reason: :no_active_subscription)])
      expect(alert.all_triggered_alerts).to be_empty
    end
  end

  context "when the thresholds were edited after the creation" do
    before do
      travel_to(alert_created_at + 2.minutes) do
        alert.thresholds.create!(value: 300, code: "edited", organization:)
      end
    end

    it "skips the alert" do
      expect(result.report).to eq([entry(status: :skipped, reason: :thresholds_edited)])
      expect(alert.all_triggered_alerts).to be_empty
    end
  end

  context "when a threshold was saved within the creation tolerance" do
    before do
      travel_to(alert_created_at + 30.seconds) do
        alert.thresholds.create!(value: 300, code: "late", organization:)
      end
    end

    it "announces the alert" do
      expect(result.report).to eq([entry(status: :announced, thresholds: [50, 100])])
    end
  end

  context "when the billing period of a current usage alert ended since its creation" do
    let(:alert_created_at) { Time.zone.parse("2026-02-20T09:00:00Z") }

    it "skips the alert" do
      expect(result.report).to eq([entry(status: :skipped, reason: :period_ended)])
      expect(alert.all_triggered_alerts).to be_empty
    end
  end

  context "when a current usage alert was last evaluated before the current period" do
    let(:alert_created_at) { Time.zone.parse("2026-03-01T00:00:00Z") }
    let(:last_processed_at) { Time.zone.parse("2026-02-28T23:00:00Z") }

    it "skips the alert" do
      expect(result.report).to eq([entry(status: :skipped, reason: :period_ended)])
    end
  end

  context "when a current usage alert on a recurring metric was created in an earlier period" do
    let(:alert_created_at) { Time.zone.parse("2026-02-20T09:00:00Z") }
    let(:alert_metric) { create(:sum_billable_metric, :recurring, organization:) }

    it "announces the alert, whose baseline carries over renewals" do
      expect(result.report).to eq([entry(status: :announced, thresholds: [50, 100])])
    end
  end

  context "when a lifetime usage alert was created in an earlier period" do
    let(:alert_factory) { :billable_metric_lifetime_usage_units_alert }
    let(:alert_created_at) { Time.zone.parse("2026-02-20T09:00:00Z") }

    it "announces the alert without the period rule" do
      expect(result.report).to eq([entry(status: :announced, thresholds: [50, 100])])
    end
  end

  context "when the alert is deleted while the task waits for its lock" do
    before do
      allow_any_instance_of(UsageMonitoring::Alert).to receive(:lock!).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
        UsageMonitoring::Alert.where(id: original.receiver.id).update_all(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        original.call(*args)
      end
    end

    it "skips the alert" do
      expect(result.report).to eq([entry(status: :skipped, reason: :discarded)])
      expect(alert.all_triggered_alerts).to be_empty
    end
  end

  context "with alerts outside the window or of another organization" do
    let(:before_window) do
      travel_to(Time.zone.parse("2026-02-01T00:00:00Z")) do
        create(:billable_metric_lifetime_usage_units_alert, organization:, subscription_external_id: subscription.external_id,
          billable_metric:, thresholds: [50], previous_value: 150, last_processed_at:)
      end
    end
    let(:other_organization_alert) do
      other_organization = create(:organization)
      travel_to(alert_created_at) do
        create(:billable_metric_lifetime_usage_units_alert, organization: other_organization, thresholds: [50],
          billable_metric: create(:billable_metric, organization: other_organization), previous_value: 150, last_processed_at:)
      end
    end
    let(:wallet_alert) do
      travel_to(alert_created_at) do
        create(:wallet_balance_amount_alert, organization:, thresholds: [50], previous_value: 10, last_processed_at:)
      end
    end

    before do
      before_window
      other_organization_alert
      wallet_alert
    end

    it "only considers the subscription alerts of the organization created in the window" do
      expect(result.report).to eq([entry(status: :announced, thresholds: [50, 100])])
      expect(UsageMonitoring::TriggeredAlert.triggered.pluck(:usage_monitoring_alert_id)).to eq([alert.id])
    end

    context "without an organization" do
      let(:organization_id) { nil }

      it "considers the alerts of every organization" do
        expect(result.report).to match_array([
          entry(status: :announced, thresholds: [50, 100]),
          entry(status: :announced, thresholds: [50], alert: other_organization_alert)
        ])
      end
    end
  end
end
