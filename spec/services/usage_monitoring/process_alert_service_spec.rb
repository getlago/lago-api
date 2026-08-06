# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::ProcessAlertService do
  describe "#call" do
    subject(:result) { described_class.call(alert:, alertable: subscription, current_metrics:) }

    let(:organization) { create(:organization) }
    let(:alert) { create(:usage_current_amount_alert, recurring_threshold: 35, thresholds: [10, 20], previous_value: 4, code: "test", organization:, subscription_external_id: subscription.external_id) }
    let(:subscription) { create(:subscription, organization:) }

    context "when locking" do
      let(:current_metrics) { instance_double(SubscriptionUsage, amount_cents: 5) }

      it "uses with_lock to prevent racing a config change" do
        allow(alert).to receive(:with_lock).and_call_original
        described_class.call(alert:, alertable: subscription, current_metrics:)

        expect(alert).to have_received(:with_lock)
      end
    end

    context "when no thresholds are crossed" do
      let(:current_metrics) { instance_double(SubscriptionUsage, amount_cents: 5) }

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
      let(:current_metrics) { instance_double(SubscriptionUsage, amount_cents: 22) }

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

    context "when recurring thresholds are crossed" do
      let(:current_metrics) { instance_double(SubscriptionUsage, amount_cents: 161) }

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
      before do
        allow(UsageMonitoring::TriggeredAlert).to receive(:create!).and_raise(StandardError)
      end

      it "does not update alert last_processed_at or previous_value" do
        expect(SendWebhookJob).not_to have_been_enqueued
        expect { result }.to raise_error(StandardError)
        expect(alert.reload.last_processed_at).to be_nil
        expect(alert.previous_value).to eq 4
      end
    end

    context "when a value comes back to the safe side" do
      let(:alert) do
        create(:usage_current_amount_alert, thresholds: [8000, 10000], previous_value: 10400, code: "rec",
          organization:, subscription_external_id: subscription.external_id)
      end
      let(:hard) { alert.thresholds.find_by(value: 10000) }
      let(:warn) { alert.thresholds.find_by(value: 8000) }
      let(:current_metrics) { instance_double(SubscriptionUsage, amount_cents: 8500) }

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
        end

        it "reports the alert as not fully resolved while a lower line is still crossed" do
          result
          resolved = alert.all_triggered_alerts.find_by(kind: :resolved)

          expect(resolved.fully_resolved).to be false
          expect(resolved.in_alarm_thresholds).to eq([])
        end

        it "does not send a webhook yet" do
          result
          expect(SendWebhookJob).not_to have_been_enqueued
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
        before { hard.update!(notify_on: %w[triggered]) }

        it "stays silent" do
          create(:triggered_alert, alert:, organization:, subscription:,
            crossed_thresholds: [{code: hard.code, value: "10000.0", recurring: false}])

          expect(result).to be_success
          expect(alert.all_triggered_alerts.where(kind: :resolved)).to be_empty
        end
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
      let(:current_metrics) { instance_double(SubscriptionUsage, fees:) }

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
  end
end
