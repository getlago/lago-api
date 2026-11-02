# frozen_string_literal: true

require "rails_helper"

require "rake"

RSpec.describe "usage_monitoring:announce_missed_thresholds" do # rubocop:disable RSpec/DescribeClass
  let(:task) { Rake::Task["usage_monitoring:announce_missed_thresholds"] }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:) }

  let(:from) { "2026-10-01T00:00:00Z" }
  let(:to) { "2026-10-31T00:00:00Z" }

  let(:alert) { create_alert(created_at: Time.zone.parse("2026-10-10T09:00:00Z")) }

  before do
    Rake.application.rake_require("tasks/usage_monitoring")
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
      expect { task.invoke(from) }.to raise_error(SystemExit).and output(/Usage: rake usage_monitoring:announce_missed_thresholds/).to_stderr
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
end
