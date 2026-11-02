# frozen_string_literal: true

require "rails_helper"

require "rake"

RSpec.describe "migrations:announce_missed_alert_thresholds" do # rubocop:disable RSpec/DescribeClass
  let(:task) { Rake::Task["migrations:announce_missed_alert_thresholds"] }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:) }

  let(:from) { "2026-10-01T00:00:00Z" }
  let(:to) { "2026-10-31T00:00:00Z" }

  let(:alert) { create_alert(created_at: Time.zone.parse("2026-10-10T09:00:00Z")) }

  before do
    Rake.application.rake_require("tasks/migrations/announce_missed_alert_thresholds")
    Rake::Task.define_task(:environment)
    task.reenable
  end

  # The creation baseline state: usage at creation stored as previous_value, already evaluated
  def create_alert(created_at:, organization: self.organization, subscription: self.subscription, code: "baseline", previous_value: 150)
    travel_to(created_at) do
      create(
        :lifetime_usage_amount_alert,
        organization:,
        subscription_external_id: subscription.external_id,
        code:,
        thresholds: [50, 100, 200],
        previous_value:,
        last_processed_at: created_at + 1.hour
      )
    end
  end

  context "without DRY_RUN" do
    before { alert }

    it "lists the alert with the thresholds it would announce and sends nothing" do
      expect { task.invoke(from, to) }
        .to output(
          a_string_including(
            "[DRY RUN]",
            "alert=#{alert.id} organization=#{organization.id} type=lifetime_usage_amount code=baseline " \
              "status=would_announce previous_value=150.0 thresholds=50.0,100.0",
            "Totals by status: would_announce=1"
          )
        ).to_stdout
        .and not_change(UsageMonitoring::TriggeredAlert, :count)

      expect(SendWebhookJob).not_to have_been_enqueued
    end
  end

  context "when DRY_RUN is false" do
    around do |example|
      ENV["DRY_RUN"] = "false"
      example.run
    ensure
      ENV["DRY_RUN"] = nil
    end

    before { alert }

    it "records one triggered row and sends alert.triggered" do
      expect { task.invoke(from, to) }
        .to output(
          a_string_including(
            "[LIVE]",
            "alert=#{alert.id} organization=#{organization.id} type=lifetime_usage_amount code=baseline " \
              "status=announced previous_value=150.0 thresholds=50.0,100.0",
            "Totals by status: announced=1"
          )
        ).to_stdout

      triggered_alert = alert.triggered_alerts.sole
      expect(triggered_alert).to have_attributes(kind: "triggered", previous_value: 0, current_value: 150)
      expect(SendWebhookJob).to have_been_enqueued.with("alert.triggered", triggered_alert)
    end
  end

  context "with alerts outside the window or of another organization" do
    let(:other_organization) { create(:organization) }
    let(:other_subscription) do
      create(:subscription, organization: other_organization, customer: create(:customer, organization: other_organization))
    end
    let(:before_window) do
      create_alert(
        created_at: Time.zone.parse("2026-09-30T23:59:00Z"),
        subscription: create(:subscription, organization:, customer:),
        code: "before"
      )
    end
    let(:after_window) do
      create_alert(
        created_at: Time.zone.parse("2026-10-31T00:01:00Z"),
        subscription: create(:subscription, organization:, customer:),
        code: "after"
      )
    end
    let(:other_alert) do
      create_alert(
        created_at: Time.zone.parse("2026-10-10T09:00:00Z"),
        organization: other_organization,
        subscription: other_subscription,
        code: "other"
      )
    end

    before do
      alert
      before_window
      after_window
      other_alert
    end

    it "lists only the alerts of the organization created in the window" do
      output = capture_stdout { task.invoke(from, to, organization.id) }

      expect(output).to include("organization=#{organization.id}", "alert=#{alert.id}", "Totals by status: would_announce=1")
      expect(output).not_to include(before_window.id, after_window.id, other_alert.id)
    end
  end

  context "when an alert is skipped" do
    let(:alert) { create_alert(created_at: Time.zone.parse("2026-10-10T09:00:00Z"), previous_value: 10) }

    before { alert }

    it "prints the alert with its reason" do
      expect { task.invoke(from, to) }
        .to output(
          a_string_including(
            "alert=#{alert.id} organization=#{organization.id} type=lifetime_usage_amount code=baseline " \
              "status=skipped previous_value=10.0 thresholds= reason=below_thresholds",
            "Totals by status: skipped=1",
            "Totals by skip reason: below_thresholds=1"
          )
        ).to_stdout
    end
  end

  context "without the organization_id argument" do
    let(:other_organization) { create(:organization) }
    let(:other_alert) do
      create_alert(
        created_at: Time.zone.parse("2026-10-10T09:00:00Z"),
        organization: other_organization,
        subscription: create(:subscription, organization: other_organization, customer: create(:customer, organization: other_organization)),
        code: "other"
      )
    end

    before do
      alert
      other_alert
    end

    it "lists the alerts of every organization" do
      output = capture_stdout { task.invoke(from, to) }

      expect(output).to include("organization: all", "alert=#{alert.id}", "alert=#{other_alert.id}")
    end
  end

  context "with a missing argument" do
    it "aborts with a usage message" do
      expect { task.invoke(from) }.to raise_error(SystemExit).and output(/Usage: rake migrations:announce_missed_alert_thresholds/).to_stderr
    end
  end

  context "with an invalid from" do
    before { alert }

    it "aborts and creates nothing" do
      expect { task.invoke("not-a-date", to) }
        .to raise_error(SystemExit)
        .and output(/Invalid from or to/).to_stderr
        .and not_change(UsageMonitoring::TriggeredAlert, :count)
    end
  end

  context "with a from that Time.zone.parse cannot read" do
    it "aborts with a usage message" do
      expect { task.invoke("2026-13-45", to) }.to raise_error(SystemExit).and output(/Invalid from or to/).to_stderr
    end
  end

  context "when from is after to" do
    it "aborts with a usage message" do
      expect { task.invoke(to, from) }.to raise_error(SystemExit).and output(/from must be before to/).to_stderr
    end
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  describe "AnnounceMissedAlertThresholds" do
    subject(:report) { travel_to(now) { AnnounceMissedAlertThresholds.call(from:, to:, organization_id:, dry_run:) } }

    before_all { Rake.application.rake_require("tasks/migrations/announce_missed_alert_thresholds") }

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
        expect { report }.to have_enqueued_job_after_commit(SendWebhookJob)
          .with("alert.triggered", instance_of(UsageMonitoring::TriggeredAlert))

        expect(report).to eq([entry(status: :announced, thresholds: [50, 100])])

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
        expect { report }.not_to change { alert.reload.attributes }
        expect(seeded.reload).to have_attributes(kind: "seeded", current_value: 150, updated_at: seeded.updated_at)
        expect(alert.all_triggered_alerts.seeded.sole).to eq(seeded)
      end

      context "when it runs as a dry run" do
        subject(:report) { travel_to(now) { AnnounceMissedAlertThresholds.call(from:, to:, organization_id:) } }

        it "reports what it would announce and writes nothing" do
          expect(report).to eq([entry(status: :would_announce, thresholds: [50, 100])])
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
        expect(report).to eq([entry(status: :announced, thresholds: [50, 100, 200, 300])])
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
        expect(report).to eq([entry(status: :skipped, reason: :below_thresholds)])
        expect(alert.all_triggered_alerts).to be_empty
        expect(SendWebhookJob).not_to have_been_enqueued
      end
    end

    context "when a triggered row already covers the missed lines" do
      before do
        create(:triggered_alert, alert:, organization:, subscription:, current_value: 120, previous_value: 0)
      end

      it "skips the alert" do
        expect(report).to eq([entry(status: :skipped, reason: :already_announced)])
        expect(alert.triggered_alerts.count).to eq(1)
        expect(SendWebhookJob).not_to have_been_enqueued
      end
    end

    context "when a triggered row covers only the lower missed lines" do
      before do
        create(:triggered_alert, alert:, organization:, subscription:, current_value: 60, previous_value: 0)
      end

      it "announces the lines above it" do
        expect(report).to eq([entry(status: :announced, thresholds: [100])])
        expect(alert.triggered_alerts.order(:current_value).last.crossed_thresholds)
          .to eq([{"code" => "warn100", "value" => "100.0", "recurring" => false}])
      end
    end

    context "when a triggered row stopped exactly on a missed line" do
      before do
        create(:triggered_alert, alert:, organization:, subscription:, current_value: 100, previous_value: 0)
      end

      it "does not announce that line again" do
        expect(report).to eq([entry(status: :skipped, reason: :already_announced)])
        expect(alert.triggered_alerts.count).to eq(1)
        expect(SendWebhookJob).not_to have_been_enqueued
      end
    end

    context "when the task runs a second time" do
      before { travel_to(now) { AnnounceMissedAlertThresholds.call(from:, to:, organization_id:, dry_run: false) } }

      it "skips the alert it already announced" do
        expect(report).to eq([entry(status: :skipped, reason: :already_announced)])
        expect(alert.triggered_alerts.count).to eq(1)
      end
    end

    context "when the alert was never evaluated" do
      let(:last_processed_at) { nil }

      it "skips the alert" do
        expect(report).to eq([entry(status: :skipped, reason: :never_evaluated)])
        expect(alert.all_triggered_alerts).to be_empty
      end
    end

    context "when the subscription is not active" do
      let(:alert_subscription) do
        create(:subscription, :terminated, organization:, customer:, plan:, external_id: "terminated-sub")
      end

      it "skips the alert" do
        expect(report).to eq([entry(status: :skipped, reason: :no_active_subscription)])
        expect(alert.all_triggered_alerts).to be_empty
      end
    end

    context "when the thresholds were edited after the creation" do
      before do
        travel_to(alert_created_at + 61.seconds) do
          alert.thresholds.create!(value: 300, code: "edited", organization:)
        end
      end

      it "skips the alert" do
        expect(report).to eq([entry(status: :skipped, reason: :thresholds_edited)])
        expect(alert.all_triggered_alerts).to be_empty
      end
    end

    context "when a threshold was saved within the creation tolerance" do
      before do
        travel_to(alert_created_at + 59.seconds) do
          alert.thresholds.create!(value: 300, code: "late", organization:)
        end
      end

      it "announces the alert" do
        expect(report).to eq([entry(status: :announced, thresholds: [50, 100])])
      end
    end

    context "when the billing period of a current usage alert ended since its creation" do
      let(:alert_created_at) { Time.zone.parse("2026-02-20T09:00:00Z") }

      it "skips the alert" do
        expect(report).to eq([entry(status: :skipped, reason: :period_ended)])
        expect(alert.all_triggered_alerts).to be_empty
      end
    end

    context "when a current usage alert was last evaluated before the current period" do
      let(:alert_created_at) { Time.zone.parse("2026-03-01T00:00:00Z") }
      let(:last_processed_at) { Time.zone.parse("2026-02-28T23:00:00Z") }

      it "skips the alert" do
        expect(report).to eq([entry(status: :skipped, reason: :period_ended)])
      end
    end

    context "when the monthly charges period of a yearly plan renewed since the last evaluation" do
      let(:yearly_plan) { create(:plan, organization:, interval: :yearly, bill_charges_monthly: true) }
      let(:alert_subscription) do
        create(:subscription, :calendar, organization:, customer:, plan: yearly_plan, external_id: "yearly-sub",
          started_at: Time.zone.parse("2026-01-01T00:00:00Z"))
      end
      # The yearly period starts on 2026-01-01, the monthly charges period on 2026-04-01
      let(:now) { Time.zone.parse("2026-04-15T12:00:00Z") }
      let(:last_processed_at) { Time.zone.parse("2026-03-31T11:00:00Z") }

      it "skips the alert" do
        expect(report).to eq([entry(status: :skipped, reason: :period_ended)])
        expect(alert.all_triggered_alerts).to be_empty
      end
    end

    context "when a current usage alert on a recurring metric was created in an earlier period" do
      let(:alert_created_at) { Time.zone.parse("2026-02-20T09:00:00Z") }
      let(:alert_metric) { create(:sum_billable_metric, :recurring, organization:) }

      it "announces the alert, whose baseline carries over renewals" do
        expect(report).to eq([entry(status: :announced, thresholds: [50, 100])])
      end
    end

    context "when a lifetime usage alert was created in an earlier period" do
      let(:alert_factory) { :billable_metric_lifetime_usage_units_alert }
      let(:alert_created_at) { Time.zone.parse("2026-02-20T09:00:00Z") }

      it "announces the alert without the period rule" do
        expect(report).to eq([entry(status: :announced, thresholds: [50, 100])])
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
        expect(report).to eq([entry(status: :skipped, reason: :discarded)])
        expect(alert.all_triggered_alerts).to be_empty
      end
    end

    context "when the alert was discarded before the run" do
      before { alert.discard }

      it "leaves it out of the report" do
        expect(UsageMonitoring::Alert.unscoped.where(id: alert.id)).to exist
        expect(report).to eq([])
        expect(UsageMonitoring::TriggeredAlert.triggered).to be_empty
        expect(SendWebhookJob).not_to have_been_enqueued
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

      it "includes alerts created exactly at from and to and excludes ones 1 second outside" do
        # One metric per alert: an alert type is unique per subscription and billable metric
        boundary_alerts = [from, to, from - 1.second, to + 1.second].map do |created_at|
          travel_to(created_at) do
            create(:billable_metric_lifetime_usage_units_alert, organization:, subscription_external_id: subscription.external_id,
              billable_metric: create(:billable_metric, organization:), thresholds: [50], previous_value: 150, last_processed_at:)
          end
        end

        expect(report.pluck(:alert_id)).to match_array([alert.id, boundary_alerts[0].id, boundary_alerts[1].id])
      end

      it "only considers the subscription alerts of the organization created in the window" do
        expect(report).to eq([entry(status: :announced, thresholds: [50, 100])])
        expect(UsageMonitoring::TriggeredAlert.triggered.pluck(:usage_monitoring_alert_id)).to eq([alert.id])
      end

      context "without an organization" do
        let(:organization_id) { nil }

        it "considers the alerts of every organization" do
          expect(report).to match_array([
            entry(status: :announced, thresholds: [50, 100]),
            entry(status: :announced, thresholds: [50], alert: other_organization_alert)
          ])
        end
      end
    end
  end
end
