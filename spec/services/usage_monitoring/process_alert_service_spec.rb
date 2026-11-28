# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::ProcessAlertService do
  describe "#call" do
    subject(:result) { described_class.call(alert:, alertable: subscription, current_metrics:) }

    let_it_be(:organization) { create_default(:organization) }
    let(:alert) { create(:usage_current_amount_alert, recurring_threshold: 35, thresholds: [10, 20], previous_value: 4, code: "test", organization:, subscription_external_id: subscription.external_id) }
    let(:subscription) { create(:subscription, organization:) }
    let(:period_end) { Time.current.end_of_month.iso8601 }

    before_all do
      create_default(:customer)
      create_default(:plan)
    end

    context "when locking" do
      let(:current_metrics) { instance_double(SubscriptionUsage, to_datetime: period_end, amount_cents: 5) }

      it "uses with_lock to prevent racing a config change" do
        allow(alert).to receive(:with_lock).and_call_original
        described_class.call(alert:, alertable: subscription, current_metrics:)

        expect(alert).to have_received(:with_lock)
      end
    end

    context "when the metric changed after the caller measured usage" do
      subject(:result) do
        described_class.call(alert:, alertable: subscription, current_metrics:, expected_billable_metric_id: measured_metric.id)
      end

      let(:current_metrics) { instance_double(SubscriptionUsage, to_datetime: period_end, amount_cents: 50) }
      let(:measured_metric) { create(:billable_metric, organization:) }

      it "skips the evaluation rather than measuring it against the new configuration" do
        expect(result).to be_success
        expect(organization.triggered_alerts.count).to eq 0
        expect(SendWebhookJob).not_to have_been_enqueued
      end

      it "leaves the evaluation time untouched, so the next run picks it up" do
        expect(result).to be_success
        expect(alert.reload.last_processed_at).to be_nil
      end
    end

    context "when the alert is deleted after the caller loaded it" do
      let(:current_metrics) { instance_double(SubscriptionUsage, to_datetime: period_end, amount_cents: 15) }

      before { UsageMonitoring::Alert.find(alert.id).discard! }

      it "skips the evaluation" do
        expect(result).to be_success
        expect(organization.triggered_alerts.count).to eq 0
        expect(SendWebhookJob).not_to have_been_enqueued
        expect(alert.reload).to have_attributes(last_processed_at: nil, previous_value: 4)
      end
    end

    context "when no thresholds are crossed" do
      let(:current_metrics) { instance_double(SubscriptionUsage, to_datetime: period_end, amount_cents: 5) }

      it "updates alert last_processed_at and previous_value" do
        expect(result).to be_success
        result_alert = result.alert
        expect(result_alert.last_processed_at).to be_within(5.seconds).of(Time.current)
        expect(result_alert.previous_value).to eq 5
        expect(organization.triggered_alerts.count).to eq 0
        expect(SendWebhookJob).not_to have_been_enqueued
      end
    end

    context "when 2 thresholds are crossed" do
      let(:current_metrics) { instance_double(SubscriptionUsage, to_datetime: period_end, amount_cents: 22) }

      it "triggers the alert" do
        expect(result).to be_success
        result_alert = result.alert
        expect(result_alert.last_processed_at).to be_within(5.seconds).of(Time.current)
        expect(result_alert.previous_value).to eq 22

        ta = organization.triggered_alerts.sole
        expect(ta.alert).to eq(alert)
        expect(ta.organization).to eq(alert.organization)
        expect(ta.subscription).to eq(subscription)
        expect(ta.current_value).to eq(22)
        expect(ta.previous_value).to eq(4)
        expect(ta.triggered_at).to be_within(5.seconds).of(Time.current)
        expect(ta.crossed_thresholds.map(&:symbolize_keys)).to contain_exactly(
          {code: "warn10", value: "10.0", recurring: false},
          {code: "warn20", value: "20.0", recurring: false}
        )

        expect(SendWebhookJob).to have_been_enqueued.once.with("alert.triggered", ta)
      end
    end

    context "when a lifetime usage alert was created above a line", :premium do
      # A fresh copy, so the shared organization stays frozen while this one gets the integration
      let(:lifetime_organization) { Organization.find(organization.id) }
      let(:alert) do
        UsageMonitoring::CreateAlertService.call!(
          organization: lifetime_organization,
          alertable: subscription,
          params: {alert_type: "lifetime_usage_amount", code: "lifetime", thresholds: [{code: "warn80", value: 80}]}
        ).alert
      end
      let(:current_metrics) { subscription.lifetime_usage.reload }

      before do
        lifetime_organization.update!(premium_integrations: ["lifetime_usage"])
        create(:lifetime_usage, organization:, subscription:, historical_usage_amount_cents: 90)
      end

      it "triggers the line on the first evaluation" do
        expect(result).to be_success

        triggered = alert.all_triggered_alerts.sole
        expect(triggered).to have_attributes(kind: "triggered", previous_value: 0, current_value: 90)
        expect(triggered.crossed_thresholds.map(&:symbolize_keys)).to eq([{code: "warn80", value: "80.0", recurring: false}])
        expect(SendWebhookJob).to have_been_enqueued.once.with("alert.triggered", triggered)
      end
    end

    context "when recurring thresholds are crossed" do
      let(:current_metrics) { instance_double(SubscriptionUsage, to_datetime: period_end, amount_cents: 161) }

      it "triggers the alert" do
        expect(result).to be_success
        result_alert = result.alert
        expect(result_alert.last_processed_at).to be_within(5.seconds).of(Time.current)
        expect(result_alert.previous_value).to eq 161

        ta = organization.triggered_alerts.sole
        expect(ta.alert).to eq(alert)
        expect(ta.organization).to eq(alert.organization)
        expect(ta.subscription).to eq(subscription)
        expect(ta.previous_value).to eq(4)
        expect(ta.current_value).to eq(161)
        expect(ta.triggered_at).to be_within(5.seconds).of(Time.current)
        expect(ta.crossed_thresholds.map(&:symbolize_keys)).to contain_exactly(
          {code: "warn10", value: "10.0", recurring: false},
          {code: "warn20", value: "20.0", recurring: false},
          {code: "rec", value: "55.0", recurring: true},
          {code: "rec", value: "90.0", recurring: true},
          {code: "rec", value: "125.0", recurring: true},
          {code: "rec", value: "160.0", recurring: true}
        )

        expect(SendWebhookJob).to have_been_enqueued.once.with("alert.triggered", ta)
      end
    end

    context "when an error occurs during TriggeredAlert creation" do
      let(:current_metrics) { instance_double(SubscriptionUsage, to_datetime: period_end, amount_cents: 15) }

      before do
        allow(UsageMonitoring::TriggeredAlert).to receive(:new).and_raise(StandardError, "history write failed")
      end

      it "does not update alert last_processed_at or previous_value" do
        expect { result }.to raise_error(StandardError, "history write failed")
        expect(alert.reload.last_processed_at).to be_nil
        expect(alert.previous_value).to eq 4
        expect(SendWebhookJob).not_to have_been_enqueued
      end
    end

    context "when a value comes back to the safe side" do
      let(:alert) do
        create(:usage_current_amount_alert, thresholds: [8000, 10000], previous_value: 10400, code: "rec",
          organization:, subscription_external_id: subscription.external_id)
      end
      let(:hard) { alert.thresholds.find_by(value: 10000) }
      let(:warn) { alert.thresholds.find_by(value: 8000) }
      let(:current_metrics) { instance_double(SubscriptionUsage, to_datetime: period_end, amount_cents: 8500) }

      before { hard.update!(notify_on: %w[triggered resolved]) }

      context "with an alarm Lago recorded" do
        before do
          create(:triggered_alert, alert:, organization:, subscription:,
            crossed_thresholds: [{code: hard.code, value: "10000.0", recurring: false}])
        end

        it "records the recovery" do
          expect(result).to be_success

          resolved = alert.all_triggered_alerts.find_by(kind: :resolved)
          expect(resolved.crossed_thresholds.map { it["code"] }).to eq([hard.code])
          expect(resolved.current_value).to eq(8500)
          expect(resolved.previous_value).to eq(10400)
          expect(resolved.resolution_reason).to eq("recovered")
        end

        it "lists the lower line still crossed, opted in or not, and reports the alert as not fully resolved" do
          result
          resolved = alert.all_triggered_alerts.find_by(kind: :resolved)

          expect(resolved.fully_resolved).to be false
          expect(resolved.in_alarm_thresholds).to eq([warn.code])
        end

        context "when the line still crossed has no code" do
          before { warn.update!(code: nil) }

          it "names it by its value" do
            result
            resolved = alert.all_triggered_alerts.find_by(kind: :resolved)

            expect(resolved.in_alarm_thresholds).to eq(["8000.0"])
          end
        end

        it "sends the resolution webhook" do
          result
          resolved = alert.all_triggered_alerts.find_by(kind: :resolved)

          expect(SendWebhookJob).to have_been_enqueued.once.with("alert.resolved", resolved)
        end

        context "when a watched line is also still crossed" do
          before { warn.update!(notify_on: %w[triggered resolved]) }

          it "lists it as still in alarm" do
            result
            resolved = alert.all_triggered_alerts.find_by(kind: :resolved)

            expect(resolved.in_alarm_thresholds).to eq([warn.code])
            expect(resolved.fully_resolved).to be false
          end
        end
      end

      context "when a line has no code" do
        before do
          hard.update!(code: nil, notify_on: %w[triggered resolved])
          create(:triggered_alert, alert:, organization:, subscription:,
            crossed_thresholds: [{code: nil, value: "10000.0", recurring: false}])
        end

        it "stays silent rather than pairing on a blank code" do
          expect(result).to be_success
          expect(alert.all_triggered_alerts.where(kind: :resolved)).to be_empty
        end
      end

      context "without an alarm Lago recorded" do
        it "stays silent" do
          expect(result).to be_success
          expect(alert.all_triggered_alerts.where(kind: :resolved)).to be_empty
        end
      end

      context "when the line is not opted in" do
        before do
          hard.update!(notify_on: %w[triggered])
          create(:triggered_alert, alert:, organization:, subscription:,
            crossed_thresholds: [{code: hard.code, value: "10000.0", recurring: false}])
        end

        it "stays silent" do
          expect(result).to be_success
          expect(alert.all_triggered_alerts.where(kind: :resolved)).to be_empty
          expect(SendWebhookJob).not_to have_been_enqueued
        end
      end
    end

    context "when a wallet balance comes back above a seeded line" do
      subject(:result) { described_class.call(alert:, alertable: wallet, current_metrics: wallet) }

      let(:wallet) { create(:wallet, organization:, balance_cents: 5000) }
      let(:alert) do
        create(:wallet_balance_amount_alert, thresholds: nil, wallet:, organization:, previous_value: 0)
      end

      before do
        create(:alert_threshold, alert:, organization:, code: "low", value: 1000, notify_on: %w[triggered resolved])
        create(:triggered_alert, alert:, organization:, kind: :seeded, subscription: nil, wallet:,
          crossed_thresholds: [{code: "low", value: "1000.0", recurring: false}])
      end

      it "announces the recovery the seeded alarm paired with" do
        expect(result).to be_success

        resolved = alert.all_triggered_alerts.where(kind: :resolved).sole
        expect(resolved).to have_attributes(
          wallet:, subscription: nil, resolution_reason: "recovered", fully_resolved: true, in_alarm_thresholds: []
        )
        expect(resolved.crossed_thresholds.map { it["code"] }).to eq(%w[low])
      end
    end

    context "when the last evaluation is from a previous period" do
      let(:period_start) { Time.current.beginning_of_month }
      let(:alert) do
        create(:usage_current_amount_alert, thresholds: [10, 20], previous_value: 90, code: "roll",
          last_processed_at: period_start - 1.day, organization:, subscription_external_id: subscription.external_id)
      end
      let(:current_metrics) { instance_double(SubscriptionUsage, to_datetime: period_end, amount_cents: 15, from_datetime: period_start.iso8601) }

      before do
        alert.thresholds.each { it.update!(notify_on: %w[triggered resolved]) }
        create(:triggered_alert, alert:, organization:, subscription:,
          crossed_thresholds: [{code: alert.thresholds.find_by(value: 20).code, value: "20.0", recurring: false}])
      end

      it "fires the thresholds the new period already crossed" do
        recorded_before = alert.all_triggered_alerts.pluck(:id)
        expect(result).to be_success

        triggered = alert.all_triggered_alerts.where.not(id: recorded_before).sole
        expect(triggered).to be_triggered
        expect(triggered.crossed_thresholds.map { it["value"] }).to eq(%w[10.0])
        expect(triggered.previous_value).to eq(0)
      end

      it "does not report a recovery at the boundary" do
        result
        expect(alert.all_triggered_alerts.where(kind: :resolved)).to be_empty
      end

      context "when the new period opens above the old value" do
        let(:current_metrics) { instance_double(SubscriptionUsage, to_datetime: period_end, amount_cents: 95, from_datetime: period_start.iso8601) }

        it "fires every threshold the new period crossed, not only those above the old value" do
          recorded_before = alert.all_triggered_alerts.pluck(:id)
          expect(result).to be_success

          triggered = alert.all_triggered_alerts.where.not(id: recorded_before).sole
          expect(triggered.crossed_thresholds.map { it["value"] }).to eq(%w[10.0 20.0])
          expect(triggered.previous_value).to eq(0)
        end
      end

      context "when a charge on the plan meters a recurring metric" do
        # A recurring billable metric aggregates from subscription start, so the plan total does not reset.
        let(:subscription) { create(:subscription, organization:, plan: recurring_plan) }
        let(:recurring_plan) { create(:plan, organization:) }
        let(:current_metrics) { instance_double(SubscriptionUsage, to_datetime: period_end, amount_cents: 90, from_datetime: period_start.iso8601) }

        before do
          create(:standard_charge, plan: recurring_plan, organization:,
            billable_metric: create(:sum_billable_metric, :recurring, organization:))
        end

        it "keeps the baseline and does not re-fire across two consecutive boundaries" do
          expect do
            described_class.call(alert:, alertable: subscription, current_metrics:)
            alert.update!(last_processed_at: period_start - 1.day)
            described_class.call(alert:, alertable: subscription, current_metrics:)
          end.not_to change { alert.all_triggered_alerts.count }
        end
      end

      context "when a continuous metric recovers across the boundary" do
        let(:subscription) { create(:subscription, organization:, plan: recurring_plan) }
        let(:recurring_plan) { create(:plan, organization:) }
        let(:current_metrics) { instance_double(SubscriptionUsage, to_datetime: period_end, amount_cents: 15, from_datetime: period_start.iso8601) }

        before do
          create(:standard_charge, plan: recurring_plan, organization:,
            billable_metric: create(:sum_billable_metric, :recurring, organization:))
        end

        it "still announces the recovery, because its window never restarted" do
          expect(result).to be_success

          resolved = alert.all_triggered_alerts.where(kind: :resolved).sole
          expect(resolved.crossed_thresholds.map { it["value"] }).to eq(%w[20.0])
          expect(resolved.current_value).to eq(15)
        end
      end

      context "when the plan mixes recurring and non-recurring charges" do
        # The non-recurring charges restart each period, so the plan amount falls at renewal although nothing recovered.
        let(:subscription) { create(:subscription, organization:, plan: mixed_plan) }
        let(:mixed_plan) { create(:plan, organization:) }

        before do
          create(:standard_charge, plan: mixed_plan, organization:,
            billable_metric: create(:sum_billable_metric, :recurring, organization:))
          create(:standard_charge, plan: mixed_plan, organization:,
            billable_metric: create(:sum_billable_metric, organization:))
        end

        it "resets the baseline instead of reporting a recovery" do
          recorded_before = alert.all_triggered_alerts.pluck(:id)
          expect(result).to be_success

          expect(alert.all_triggered_alerts.where(kind: :resolved)).to be_empty
          triggered = alert.all_triggered_alerts.where.not(id: recorded_before).sole
          expect(triggered.crossed_thresholds.map { it["value"] }).to eq(%w[10.0])
          expect(triggered.previous_value).to eq(0)
        end
      end

      context "when the alert watches one non-recurring billable metric" do
        let(:billable_metric) { create(:sum_billable_metric, organization:) }
        let(:charge) { create(:standard_charge, plan: subscription.plan, organization:, billable_metric:) }
        let(:alert) do
          create(:billable_metric_current_usage_amount_alert, thresholds: [10, 20], previous_value: 90, code: "roll-bm-amount",
            last_processed_at: period_start - 1.day, organization:, billable_metric:,
            subscription_external_id: subscription.external_id)
        end
        let(:current_metrics) do
          instance_double(SubscriptionUsage, to_datetime: period_end, from_datetime: period_start.iso8601,
            fees: [instance_double(Fee, charge_id: charge.id, amount_cents: 15)])
        end

        it "resets the baseline and fires what the new period crossed" do
          recorded_before = alert.all_triggered_alerts.pluck(:id)
          expect(result).to be_success

          triggered = alert.all_triggered_alerts.where.not(id: recorded_before).sole
          expect(triggered).to be_triggered
          expect(triggered.crossed_thresholds.map { it["value"] }).to eq(%w[10.0])
          expect(triggered.previous_value).to eq(0)
        end
      end

      context "when the alert watches units of one non-recurring billable metric" do
        let(:billable_metric) { create(:sum_billable_metric, organization:) }
        let(:charge) { create(:standard_charge, plan: subscription.plan, organization:, billable_metric:) }
        let(:alert) do
          create(:billable_metric_current_usage_units_alert, thresholds: [10, 20], previous_value: 90, code: "roll-bm-units",
            last_processed_at: period_start - 1.day, organization:, billable_metric:,
            subscription_external_id: subscription.external_id)
        end
        let(:current_metrics) do
          instance_double(SubscriptionUsage, to_datetime: period_end, from_datetime: period_start.iso8601,
            fees: [instance_double(Fee, charge_id: charge.id, units: 15)])
        end

        it "resets the baseline and fires what the new period crossed" do
          recorded_before = alert.all_triggered_alerts.pluck(:id)
          expect(result).to be_success

          triggered = alert.all_triggered_alerts.where.not(id: recorded_before).sole
          expect(triggered).to be_triggered
          expect(triggered.crossed_thresholds.map { it["value"] }).to eq(%w[10.0])
          expect(triggered.previous_value).to eq(0)
        end
      end

      context "when the alert watches one recurring billable metric" do
        let(:billable_metric) { create(:sum_billable_metric, :recurring, organization:) }
        let(:alert) do
          create(:billable_metric_current_usage_amount_alert, thresholds: [10, 20], previous_value: 90, code: "roll-bm",
            last_processed_at: period_start - 1.day, organization:, billable_metric:,
            subscription_external_id: subscription.external_id)
        end
        let(:charge) { create(:standard_charge, plan: subscription.plan, organization:, billable_metric:) }
        let(:current_metrics) do
          instance_double(SubscriptionUsage, to_datetime: period_end, from_datetime: period_start.iso8601,
            fees: [instance_double(Fee, charge_id: charge.id, amount_cents: 90)])
        end

        it "keeps the baseline because a recurring metric never restarts" do
          expect { result }.not_to change { alert.all_triggered_alerts.count }
        end
      end

      context "when the alert counts lifetime usage" do
        let(:alert) do
          create(:lifetime_usage_amount_alert, thresholds: [10, 20], previous_value: 90, code: "roll",
            last_processed_at: period_start - 1.day, organization:,
            subscription_external_id: subscription.external_id)
        end
        let(:current_metrics) { instance_double(LifetimeUsage, total_amount_cents: 90) }

        it "does not re-fire across two consecutive boundaries" do
          expect do
            described_class.call(alert:, alertable: subscription, current_metrics:)
            alert.update!(last_processed_at: period_start - 1.day)
            described_class.call(alert:, alertable: subscription, current_metrics:)
          end.not_to change { alert.all_triggered_alerts.count }
        end
      end
    end

    context "when the usage was measured before a renewal and processed after it" do
      let(:period_start) { Time.current.beginning_of_month }
      let(:alert) do
        create(:usage_current_amount_alert, thresholds: [10, 20], previous_value: 0, code: "late",
          organization:, subscription_external_id: subscription.external_id)
      end
      let(:old_period_usage) do
        instance_double(SubscriptionUsage, amount_cents: 90, from_datetime: (period_start - 1.month).iso8601,
          to_datetime: (period_start - 1.second).iso8601)
      end
      let(:new_period_usage) do
        instance_double(SubscriptionUsage, amount_cents: 15, from_datetime: period_start.iso8601, to_datetime: period_end)
      end

      before do
        alert.thresholds.each { it.update!(notify_on: %w[triggered resolved]) }
      end

      it "dates the evaluation at the end of the measured period" do
        described_class.call(alert:, alertable: subscription, current_metrics: old_period_usage)

        expect(alert.reload.last_processed_at).to eq(period_start - 1.second)
      end

      it "treats the next evaluation as the start of a new period" do
        described_class.call(alert:, alertable: subscription, current_metrics: old_period_usage)
        recorded_before = alert.all_triggered_alerts.pluck(:id)
        described_class.call(alert:, alertable: subscription, current_metrics: new_period_usage)

        expect(alert.all_triggered_alerts.where(kind: :resolved)).to be_empty
        triggered = alert.all_triggered_alerts.where.not(id: recorded_before).sole
        expect(triggered.crossed_thresholds.map { it["value"] }).to eq(%w[10.0])
        expect(triggered.previous_value).to eq(0)
      end
    end

    context "when usages measured at different times are processed out of order" do
      subject(:result) { described_class.call(alert:, alertable: subscription, current_metrics:, measured_at:) }

      let(:now) { Time.zone.parse("2026-11-15 12:00:00") }
      let(:period_start) { now.beginning_of_month }
      let(:alert) do
        create(:usage_current_amount_alert, thresholds: [10, 20], previous_value: 5, last_processed_at: now - 10.seconds,
          code: "order", organization:, subscription_external_id: subscription.external_id)
      end
      let(:current_metrics) do
        instance_double(SubscriptionUsage, amount_cents: 25, from_datetime: period_start.iso8601, to_datetime: period_end)
      end

      before { travel_to(now) }

      context "with a usage measured before the one last processed" do
        let(:measured_at) { now - 20.seconds }

        it "skips it, keeping the newer evaluation" do
          expect(result).to be_success
          expect(alert.all_triggered_alerts).to be_empty
          expect(alert.reload).to have_attributes(previous_value: 5, last_processed_at: now - 10.seconds)
        end
      end

      context "with a usage measured after the one last processed" do
        let(:measured_at) { now - 5.seconds }

        it "evaluates it and dates it at its measurement, not its processing" do
          expect(result).to be_success
          expect(alert.all_triggered_alerts.sole.crossed_thresholds.map { it["value"] }).to eq(%w[10.0 20.0])
          expect(alert.reload).to have_attributes(previous_value: 25, last_processed_at: now - 5.seconds)
        end
      end

      context "with a usage measured at the time of the one last processed" do
        let(:measured_at) { now - 10.seconds }

        it "evaluates it" do
          expect(result).to be_success
          expect(alert.all_triggered_alerts.count).to eq(1)
          expect(alert.reload).to have_attributes(previous_value: 25, last_processed_at: now - 10.seconds)
        end
      end
    end

    context "when usages measured around a renewal are processed out of order" do
      let(:now) { Time.zone.parse("2026-11-15 12:00:00") }
      let(:period_start) { now.beginning_of_month }
      let(:alert) do
        create(:usage_current_amount_alert, thresholds: [10, 20], previous_value: 0, code: "renewal",
          organization:, subscription_external_id: subscription.external_id)
      end
      let(:old_period_usage) do
        instance_double(SubscriptionUsage, amount_cents: 90, from_datetime: (period_start - 1.month).iso8601,
          to_datetime: (period_start - 1.second).iso8601)
      end
      let(:new_period_usage) do
        instance_double(SubscriptionUsage, amount_cents: 15, from_datetime: period_start.iso8601, to_datetime: period_end)
      end

      before { travel_to(now) }

      it "skips the old period usage measured before the new period one" do
        described_class.call(alert:, alertable: subscription, current_metrics: new_period_usage, measured_at: period_start + 1.day)
        described_class.call(alert:, alertable: subscription, current_metrics: old_period_usage, measured_at: period_start - 5.seconds)

        expect(alert.all_triggered_alerts.sole.crossed_thresholds.map { it["value"] }).to eq(%w[10.0])
        expect(alert.reload).to have_attributes(previous_value: 15, last_processed_at: period_start + 1.day)
      end

      it "treats the new period usage processed after the old one as the start of a new period" do
        described_class.call(alert:, alertable: subscription, current_metrics: old_period_usage, measured_at: period_start - 5.seconds)
        recorded_before = alert.all_triggered_alerts.pluck(:id)
        described_class.call(alert:, alertable: subscription, current_metrics: new_period_usage, measured_at: period_start + 1.day)

        expect(alert.all_triggered_alerts.where(kind: :resolved)).to be_empty
        triggered = alert.all_triggered_alerts.where.not(id: recorded_before).sole
        expect(triggered.crossed_thresholds.map { it["value"] }).to eq(%w[10.0])
        expect(triggered.previous_value).to eq(0)
      end

      it "dates a new period usage measured just before the renewal at the period start" do
        described_class.call(alert:, alertable: subscription, current_metrics: new_period_usage, measured_at: period_start - 1.second)
        next_usage = instance_double(SubscriptionUsage, amount_cents: 16, from_datetime: period_start.iso8601, to_datetime: period_end)
        described_class.call(alert:, alertable: subscription, current_metrics: next_usage, measured_at: period_start + 30.seconds)

        expect(alert.all_triggered_alerts.sole.crossed_thresholds.map { it["value"] }).to eq(%w[10.0])
        expect(alert.reload).to have_attributes(previous_value: 16, last_processed_at: period_start + 30.seconds)
      end

      # Accepted gap: last_processed_at is capped to the old period's end, so it cannot order usages measured after it.
      it "evaluates two old period usages measured after the renewal in either order" do
        later_usage = instance_double(SubscriptionUsage, amount_cents: 30, from_datetime: (period_start - 1.month).iso8601,
          to_datetime: (period_start - 1.second).iso8601)
        described_class.call(alert:, alertable: subscription, current_metrics: later_usage, measured_at: period_start + 2.seconds)
        described_class.call(alert:, alertable: subscription, current_metrics: old_period_usage, measured_at: period_start + 1.second)

        expect(alert.reload).to have_attributes(previous_value: 90, last_processed_at: period_start - 1.second)
      end
    end

    context "when billable metric is not part of the plan charges" do
      let(:alert) do
        create(
          :billable_metric_current_usage_amount_alert,
          thresholds: [10, 20],
          previous_value: 0,
          code: "test",
          organization:,
          subscription_external_id: subscription.external_id
        )
      end
      let(:other_billable_metric) { create(:billable_metric, organization:) }
      let(:charge) { create(:standard_charge, billable_metric: other_billable_metric) }
      let(:fees) { [create(:charge_fee, charge:, amount_cents: 100)] }
      let(:current_metrics) { instance_double(SubscriptionUsage, to_datetime: period_end, fees:) }

      it "returns success without triggering alert" do
        expect(result).to be_success
        expect(alert.previous_value).to eq 0
        expect(organization.triggered_alerts.count).to eq 0
        expect(SendWebhookJob).not_to have_been_enqueued
      end

      it "still records the evaluation time" do
        expect(result).to be_success
        expect(alert.reload.last_processed_at).to be_within(5.seconds).of(Time.current)
      end
    end

    context "with a wallet loaded before its balance moved" do
      subject(:result) { described_class.call(alert:, alertable: stale_wallet, current_metrics: stale_wallet) }

      let(:wallet) { create(:wallet, organization:, ongoing_balance_cents: 600) }
      let(:stale_wallet) { Wallet.find(wallet.id) }
      let(:alert) do
        create(
          :wallet_ongoing_balance_amount_alert,
          organization:,
          wallet:,
          thresholds: [500],
          previous_value: 400,
          direction: "decreasing"
        )
      end

      before do
        stale_wallet
        wallet.update!(ongoing_balance_cents: 400)
      end

      it "evaluates the balance read under the lock" do
        expect { result }.not_to change(UsageMonitoring::TriggeredAlert, :count)
        expect(alert.reload.previous_value).to eq(400)
      end
    end

    context "with a catalog wallet loaded before its balance moved" do
      subject(:result) { described_class.call(alert:, alertable: stale_wallet, current_metrics: stale_wallet) }

      let(:catalog_wallet) { create(:catalog_wallet, organization:, balance_cents: 600) }
      let(:stale_wallet) { CatalogWallet.find(catalog_wallet.id) }
      let(:alert) { create(:catalog_wallet_alert, organization:, catalog_wallet:, previous_value: 400, last_processed_at: 1.hour.ago) }

      before do
        create(:catalog_wallet_alert_threshold, organization:, catalog_wallet_alert: alert, value: 500)
        stale_wallet
        catalog_wallet.update!(balance_cents: 400)
      end

      it "evaluates the balance read under the lock" do
        expect { result }.not_to change(UsageMonitoring::CatalogWalletTriggeredAlert, :count)
        expect(alert.reload.previous_value).to eq(400)
      end
    end

    context "with a contract alert" do
      subject(:result) { evaluate(*rate_card_usages) }

      let_it_be(:contract) { create(:contract, organization:) }
      let_it_be(:llm_tokens) { create(:product, organization:) }
      let_it_be(:opus) { create(:product_filter, organization:, product: llm_tokens) }
      let_it_be(:sonnet) { create(:product_filter, organization:, product: llm_tokens) }

      let(:opus_card) { card_of(llm_tokens, opus) }
      let(:sonnet_card) { card_of(llm_tokens, sonnet) }
      let(:opus_slice) { "#{llm_tokens.id}/#{opus.id}" }
      let(:sonnet_slice) { "#{llm_tokens.id}/#{sonnet.id}" }
      let(:thresholds) { [1_000_000, 2_000_000] }
      let(:previous_value) { 0 }
      let(:previous_windows) { {} }
      let(:alert) do
        create(
          :contract_usage_units_alert,
          organization:,
          contract_external_id: contract.external_id,
          product: llm_tokens,
          product_filter: opus,
          thresholds:,
          previous_value:,
          previous_windows:
        )
      end
      let(:warn) { alert.thresholds.find_by(value: 1_000_000) }

      before { freeze_time }

      def card_of(product, product_filter = nil)
        rate_card = build_stubbed(:rate_card, organization:, product:, product_filter:)
        build_stubbed(:contract_rate_card, organization:, contract:, rate_card:)
      end

      def card_usage(contract_rate_card, started_at, units, amount_cents: 0)
        RateCardUsage.new(
          contract_rate_card:,
          billing_segment: BillingSegment.new(contract_rate_card:, started_at: Time.zone.parse(started_at)),
          rate_phase: nil,
          fees: [Fee.new(units:, amount_cents:)]
        )
      end

      def evaluate(*rate_card_usages, measured_at: nil)
        usage = Contracts::CurrentUsageService::Result.new.tap do
          it.contract = contract
          it.rate_card_usages = rate_card_usages
        end
        described_class.call!(alert:, alertable: contract, current_metrics: usage, measured_at:)
      end

      # The start of a window is stored in the customer's local time, UTC unless a spec sets a timezone
      def window(started_at, value)
        {"started_at" => started_at && Time.zone.parse(started_at).strftime("%Y-%m-%dT%H:%M:%S.%6N"), "value" => BigDecimal(value).to_s("F")}
      end

      def record_alarm(code, value)
        create(:contract_triggered_alert, alert:, organization:, contract:,
          crossed_thresholds: [{code:, value: BigDecimal(value).to_s("F"), recurring: false}])
      end

      context "when the alert is created above its thresholds" do
        let(:rate_card_usages) { [card_usage(opus_card, "2026-11-01", 2_500_000)] }

        it "triggers them all at the first evaluation, from 0" do
          expect(result).to be_success

          triggered = alert.all_triggered_alerts.sole
          expect(triggered).to have_attributes(
            kind: "triggered", contract:, previous_value: 0, current_value: 2_500_000, triggered_at: Time.current
          )
          expect(triggered.crossed_thresholds).to eq([
            {"code" => "warn1000000", "value" => "1000000.0", "recurring" => false},
            {"code" => "warn2000000", "value" => "2000000.0", "recurring" => false}
          ])
          expect(SendWebhookJob).to have_been_enqueued.once.with("alert.triggered", triggered)
          expect(alert.reload).to have_attributes(
            previous_value: 2_500_000,
            previous_windows: {opus_slice => window("2026-11-01", 2_500_000)},
            last_processed_at: Time.current
          )
        end
      end

      context "when the usage lands on a threshold" do
        let(:previous_value) { 900_000 }
        let(:previous_windows) { {opus_slice => window("2026-11-01", 900_000)} }
        let(:rate_card_usages) { [card_usage(opus_card, "2026-11-01", 1_000_000)] }

        it "triggers it" do
          expect(result).to be_success

          triggered = alert.all_triggered_alerts.sole
          expect(triggered).to have_attributes(previous_value: 900_000, current_value: 1_000_000)
          expect(triggered.crossed_thresholds).to eq([{"code" => "warn1000000", "value" => "1000000.0", "recurring" => false}])
        end
      end

      context "when the usage goes down in the same window" do
        let(:previous_value) { 2_500_000 }
        let(:previous_windows) { {opus_slice => window("2026-11-01", 2_500_000)} }
        let(:rate_card_usages) { [card_usage(opus_card, "2026-11-01", 1_500_000)] }
        let(:high) { alert.thresholds.find_by(value: 2_000_000) }

        before do
          high.update!(notify_on: %w[triggered resolved])
          record_alarm(high.code, 2_000_000)
        end

        it "never triggers, and resolves an announced threshold the usage went back under" do
          expect { result }.not_to change { alert.triggered_alerts.count }

          resolved = alert.all_triggered_alerts.find_by!(kind: :resolved)
          expect(resolved).to have_attributes(
            resolution_reason: "recovered", previous_value: 2_500_000, current_value: 1_500_000,
            in_alarm_thresholds: [warn.code], fully_resolved: false
          )
          expect(resolved.crossed_thresholds).to eq([{"code" => high.code, "value" => "2000000.0", "recurring" => false}])
          expect(SendWebhookJob).to have_been_enqueued.once.with("alert.resolved", resolved)
          expect(alert.reload.previous_windows).to eq(opus_slice => window("2026-11-01", 1_500_000))
        end
      end

      context "when the usage goes back under a threshold not opted in to resolutions" do
        let(:previous_value) { 1_200_000 }
        let(:previous_windows) { {opus_slice => window("2026-11-01", 1_200_000)} }
        let(:rate_card_usages) { [card_usage(opus_card, "2026-11-01", 900_000)] }

        before { record_alarm(warn.code, 1_000_000) }

        it "sends no webhook" do
          expect { result }.not_to change { alert.all_triggered_alerts.count }

          expect(SendWebhookJob).not_to have_been_enqueued
          expect(alert.reload).to have_attributes(
            previous_value: 900_000,
            previous_windows: {opus_slice => window("2026-11-01", 900_000)}
          )
        end
      end

      context "when no card prices the scope" do
        let(:previous_value) { 1_200_000 }
        let(:previous_windows) { {opus_slice => window("2026-11-01", 1_200_000)} }
        let(:rate_card_usages) { [card_usage(sonnet_card, "2026-11-02", 500_000)] }

        it "skips the evaluation and keeps the stored baseline" do
          expect(result).to be_success

          expect(alert.all_triggered_alerts).to be_empty
          expect(SendWebhookJob).not_to have_been_enqueued
          expect(alert.reload).to have_attributes(
            previous_value: 1_200_000,
            previous_windows: {opus_slice => window("2026-11-01", 1_200_000)},
            last_processed_at: Time.current
          )
        end
      end

      context "when the alert watches the amount of the whole contract" do
        let_it_be(:video_minutes) { create(:product, organization:) }
        let_it_be(:platform) { create(:product, :fixed, organization:) }

        let(:video_minutes_card) { card_of(video_minutes) }
        let(:platform_card) { card_of(platform) }
        let(:alert) do
          create(:contract_usage_amount_alert, organization:, contract_external_id: contract.external_id, thresholds: [150_00])
        end
        let(:rate_card_usages) do
          [
            card_usage(opus_card, "2026-11-01", 600_000, amount_cents: 80_00),
            card_usage(video_minutes_card, "2026-11-01", 90, amount_cents: 75_00),
            card_usage(platform_card, "2026-01-01", 1, amount_cents: 500_00)
          ]
        end

        it "triggers on the amount of the metered cards, in cents" do
          expect(result).to be_success

          triggered = alert.all_triggered_alerts.sole
          # opus + video_minutes, without platform's fixed 500_00
          expect(triggered).to have_attributes(previous_value: 0, current_value: 80_00 + 75_00)
          expect(triggered.crossed_thresholds).to eq([{"code" => "warn15000", "value" => "15000.0", "recurring" => false}])
          expect(SendWebhookJob).to have_been_enqueued.once.with("alert.triggered", triggered)
          expect(alert.reload.previous_windows).to eq(
            opus_slice => window("2026-11-01", 80_00),
            video_minutes.id => window("2026-11-01", 75_00)
          )
        end
      end

      context "when the card starts a new window" do
        let(:previous_value) { 1_200_000 }
        let(:previous_windows) { {opus_slice => window("2026-11-01", 1_200_000)} }
        let(:rate_card_usages) { [card_usage(opus_card, "2026-12-01", 50_000)] }

        before do
          warn.update!(notify_on: %w[triggered resolved])
          record_alarm(warn.code, 1_000_000)
        end

        it "takes the baseline back to 0 without a webhook" do
          expect { result }.not_to change { alert.all_triggered_alerts.count }

          expect(SendWebhookJob).not_to have_been_enqueued
          expect(alert.reload).to have_attributes(
            previous_value: 50_000,
            previous_windows: {opus_slice => window("2026-12-01", 50_000)}
          )
        end

        context "when the new window is already past a threshold" do
          let(:rate_card_usages) { [card_usage(opus_card, "2026-12-01", 1_100_000)] }

          it "triggers it again from 0" do
            expect(result).to be_success

            triggered = alert.triggered_alerts.find_by!(current_value: 1_100_000)
            expect(triggered).to have_attributes(previous_value: 0)
            expect(triggered.crossed_thresholds).to eq([{"code" => "warn1000000", "value" => "1000000.0", "recurring" => false}])
          end
        end
      end

      context "when the scope covers cards renewing on different cadences" do
        let(:alert) do
          create(:contract_usage_units_alert, organization:, contract_external_id: contract.external_id,
            product: llm_tokens, with_product_filters: true, thresholds: [1_000_000])
        end

        before { warn.update!(notify_on: %w[triggered resolved]) }

        it "takes only the renewed card out of the baseline, then triggers again when the threshold is crossed" do
          # Nov 7: Opus monthly since Nov 1, Sonnet weekly since Nov 2
          evaluate(card_usage(opus_card, "2026-11-01", 900_000), card_usage(sonnet_card, "2026-11-02", 700_000))
          first = alert.all_triggered_alerts.sole
          expect(first).to have_attributes(previous_value: 0, current_value: 900_000 + 700_000)

          # Nov 9: Sonnet renewed, so its 700k leaves the baseline and Opus's 900k stays
          evaluate(card_usage(opus_card, "2026-11-01", 905_000), card_usage(sonnet_card, "2026-11-09", 0))
          expect(alert.all_triggered_alerts.count).to eq(1)
          expect(alert.reload).to have_attributes(
            previous_value: 905_000,
            previous_windows: {opus_slice => window("2026-11-01", 905_000)}
          )

          # Nov 11
          evaluate(card_usage(opus_card, "2026-11-01", 950_000), card_usage(sonnet_card, "2026-11-09", 120_000))
          second = alert.all_triggered_alerts.where.not(id: first.id).sole
          expect(second).to have_attributes(kind: "triggered", previous_value: 905_000, current_value: 950_000 + 120_000)

          expect(SendWebhookJob).to have_been_enqueued.with("alert.triggered", first)
          expect(SendWebhookJob).to have_been_enqueued.with("alert.triggered", second)
          expect(SendWebhookJob).not_to have_been_enqueued.with("alert.resolved", anything)
        end
      end

      context "when usage arrives between a card's renewal and the next evaluation" do
        let(:alert) do
          create(:contract_usage_units_alert, organization:, contract_external_id: contract.external_id,
            product: llm_tokens, with_product_filters: true, thresholds: [2_000_000])
        end

        it "reports the crossing reached since the renewal" do
          # Nov 8, the last evaluation in Sonnet's old window
          evaluate(card_usage(opus_card, "2026-11-01", 990_000), card_usage(sonnet_card, "2026-11-02", 700_000))
          expect(alert.all_triggered_alerts).to be_empty

          # Nov 9 10:00, the first evaluation after Sonnet renewed
          evaluate(card_usage(opus_card, "2026-11-01", 1_950_000), card_usage(sonnet_card, "2026-11-09", 60_000))

          # The baseline keeps Opus's 990k, so 2M is crossed on the way to 2.01M
          triggered = alert.all_triggered_alerts.sole
          expect(triggered).to have_attributes(previous_value: 990_000, current_value: 1_950_000 + 60_000)
          expect(triggered.crossed_thresholds).to eq([{"code" => "warn2000000", "value" => "2000000.0", "recurring" => false}])
        end
      end

      context "when a card renews while another stays in its window" do
        let(:alert) do
          create(:contract_usage_units_alert, organization:, contract_external_id: contract.external_id,
            product: llm_tokens, with_product_filters: true, thresholds:, previous_value:, previous_windows:)
        end
        let(:high) { alert.thresholds.find_by(value: 2_000_000) }
        let(:previous_value) { 1_500_000 + 600_000 }
        let(:previous_windows) do
          {opus_slice => window("2026-11-01", 1_500_000), sonnet_slice => window("2026-11-02", 600_000)}
        end

        before do
          [warn, high].each { it.update!(notify_on: %w[triggered resolved]) }
          record_alarm(warn.code, 1_000_000)
          record_alarm(high.code, 2_000_000)
        end

        context "when the renewal alone takes the usage back under a threshold" do
          let(:rate_card_usages) { [card_usage(opus_card, "2026-11-01", 1_510_000), card_usage(sonnet_card, "2026-11-09", 0)] }

          it "resolves nothing, as a renewal is not a recovery" do
            expect { result }.not_to change { alert.all_triggered_alerts.count }

            expect(SendWebhookJob).not_to have_been_enqueued
            expect(alert.reload).to have_attributes(
              previous_value: 1_510_000,
              previous_windows: {opus_slice => window("2026-11-01", 1_510_000)}
            )
          end
        end

        context "when the card still in its window goes down too" do
          let(:rate_card_usages) { [card_usage(opus_card, "2026-11-01", 800_000), card_usage(sonnet_card, "2026-11-09", 0)] }

          it "resolves the thresholds that card went back under" do
            expect(result).to be_success

            # Measured from Opus's 1.5M, the only card still in its window: 2M left the alarm with Sonnet's renewal
            resolved = alert.all_triggered_alerts.find_by!(kind: :resolved)
            expect(resolved).to have_attributes(
              resolution_reason: "recovered", previous_value: 1_500_000, current_value: 800_000,
              in_alarm_thresholds: [], fully_resolved: true
            )
            expect(resolved.crossed_thresholds).to eq([{"code" => warn.code, "value" => "1000000.0", "recurring" => false}])
            expect(SendWebhookJob).to have_been_enqueued.once.with("alert.resolved", resolved)
          end
        end
      end

      context "when an older usage reaches the alert after a newer one" do
        let(:alert) do
          create(:contract_usage_units_alert, organization:, contract_external_id: contract.external_id,
            product: llm_tokens, with_product_filters: true, thresholds: [1_000_000], previous_value: 990_000 + 700_000,
            previous_windows: {opus_slice => window("2026-11-01", 990_000), sonnet_slice => window("2026-11-02", 700_000)})
        end
        let(:renewed_at) { Time.zone.parse("2026-11-09T00:00:01Z") }

        before { record_alarm(warn.code, 1_000_000) }

        it "skips the older usage, which would cross the threshold again" do
          expect do
            # Measured just after Sonnet renewed, and processed first
            evaluate(card_usage(opus_card, "2026-11-01", 990_000), card_usage(sonnet_card, "2026-11-09", 0), measured_at: renewed_at)
            # Measured just before, still in Sonnet's old window, and processed last
            evaluate(
              card_usage(opus_card, "2026-11-01", 990_000), card_usage(sonnet_card, "2026-11-02", 700_000),
              measured_at: renewed_at - 2.seconds
            )
          end.not_to change { alert.all_triggered_alerts.count }

          expect(SendWebhookJob).not_to have_been_enqueued
          expect(alert.reload).to have_attributes(
            previous_value: 990_000,
            previous_windows: {opus_slice => window("2026-11-01", 990_000)},
            last_processed_at: renewed_at
          )
        end
      end

      context "when the customer moves to another timezone" do
        let(:contract) { create(:contract, organization:, customer: create(:customer, organization:, timezone: "Asia/Tokyo")) }
        let(:previous_value) { 1_200_000 }
        # Stored while the customer was on UTC
        let(:previous_windows) { {opus_slice => window("2026-11-01", 1_200_000)} }
        # Nov 1 at midnight in Tokyo
        let(:rate_card_usages) { [card_usage(opus_card, "2026-10-31T15:00:00Z", 1_250_000)] }

        before { record_alarm(warn.code, 1_000_000) }

        it "keeps measuring the same window, without crossing the thresholds again" do
          expect { result }.not_to change { alert.all_triggered_alerts.count }

          expect(SendWebhookJob).not_to have_been_enqueued
          expect(alert.reload).to have_attributes(
            previous_value: 1_250_000,
            previous_windows: {opus_slice => window("2026-11-01", 1_250_000)}
          )
        end
      end

      context "when a new version of the card takes over" do
        let(:previous_value) { 1_200_000 }
        let(:previous_windows) { {opus_slice => window("2026-11-01", 1_200_000)} }
        let(:opus_next_version) { card_of(llm_tokens, opus) }
        let(:rate_card_usages) { [card_usage(opus_next_version, "2026-11-15", 200_000)] }

        before do
          warn.update!(notify_on: %w[triggered resolved])
          record_alarm(warn.code, 1_000_000)
        end

        it "starts its usage from 0, without resolving what the previous version crossed" do
          expect { result }.not_to change { alert.all_triggered_alerts.count }

          expect(SendWebhookJob).not_to have_been_enqueued
          expect(alert.reload).to have_attributes(
            previous_value: 200_000,
            previous_windows: {opus_slice => window("2026-11-15", 200_000)}
          )
        end
      end

      context "when a replacement contract takes the external id" do
        let(:previous_value) { 1_200_000 }
        # Stored by the Opus card of the contract it replaces, in that contract's window
        let(:previous_windows) { {opus_slice => window("2026-11-01", 1_200_000)} }
        # The replacement's card opens its window with the contract
        let(:rate_card_usages) { [card_usage(opus_card, "2026-11-20", 1_050_000)] }

        it "evaluates the new contract from 0" do
          expect(result).to be_success

          triggered = alert.all_triggered_alerts.sole
          expect(triggered).to have_attributes(contract:, previous_value: 0, current_value: 1_050_000)
          expect(alert.reload.previous_windows).to eq(opus_slice => window("2026-11-20", 1_050_000))
        end
      end

      context "when the card meters a recurring metric" do
        let_it_be(:seats) do
          create(:product, organization:, billable_metric: create(:sum_billable_metric, :recurring, organization:))
        end

        let(:seats_card) { card_of(seats) }
        let(:alert) do
          create(:contract_usage_units_alert, organization:, contract_external_id: contract.external_id,
            product: seats, thresholds: [100], previous_value: 120, previous_windows: {seats.id => window(nil, 120)})
        end
        let(:high) { alert.thresholds.sole }
        let(:rate_card_usages) { [card_usage(seats_card, "2026-12-01", 80)] }

        before do
          high.update!(notify_on: %w[triggered resolved])
          record_alarm(high.code, 100)
        end

        it "keeps its baseline across the renewal and resolves the threshold the usage went back under" do
          expect(result).to be_success

          resolved = alert.all_triggered_alerts.find_by!(kind: :resolved)
          expect(resolved).to have_attributes(
            resolution_reason: "recovered", previous_value: 120, current_value: 80,
            in_alarm_thresholds: [], fully_resolved: true
          )
          expect(SendWebhookJob).to have_been_enqueued.once.with("alert.resolved", resolved)
          expect(alert.reload.previous_windows).to eq(seats.id => window(nil, 80))
        end

        context "when another card takes over the product" do
          # A new version, or the card of a replacement contract: either way the usage carries over
          let(:rate_card_usages) { [card_usage(card_of(seats), "2026-11-15", 125)] }

          it "keeps the baseline, without crossing the threshold again" do
            expect { result }.not_to change { alert.all_triggered_alerts.count }

            expect(SendWebhookJob).not_to have_been_enqueued
            expect(alert.reload).to have_attributes(previous_value: 125, previous_windows: {seats.id => window(nil, 125)})
          end
        end
      end
    end
  end
end
