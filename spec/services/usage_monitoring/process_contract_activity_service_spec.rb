# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::ProcessContractActivityService, :premium do
  subject(:result) { described_class.call(contract_activity:) }

  let_it_be(:organization) { create(:organization, feature_flags: %w[product_catalog contract_alerts]) }
  let_it_be(:customer) { create(:customer, organization:, timezone: "UTC", currency: "EUR") }
  let_it_be(:billable_metric) { create(:billable_metric, organization:, aggregation_type: :count_agg) }
  let_it_be(:product) { create(:product, :metered, organization:, billable_metric:) }
  let_it_be(:rate_card) { create(:rate_card, organization:, product:, currency: "EUR") }
  # The service loads the contract's alerts on it, which a shared instance would carry over to the next example
  let_it_be(:contract, refind: true) { create(:contract, organization:, customer:, started_at: Time.zone.parse("2027-01-01")) }

  let(:now) { Time.zone.parse("2027-02-10 12:00:00") }
  let(:billing_scope) { :cycle }
  let(:contract_activity) { create(:contract_activity, organization:, contract:, enqueued: true, enqueued_at: now) }
  let(:alert) do
    create(:contract_usage_units_alert, organization:, contract_external_id: contract.external_id, product:, thresholds: [1, 2])
  end

  # One monthly card at 2 EUR per event, from Jan 1, and one event in January and two in February
  before_all do
    create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2027-01-01"),
      rate_properties: {"amount" => "2"})

    %w[2027-01-10 2027-02-03 2027-02-05].each do |day|
      create(:event, organization:, customer:, external_subscription_id: contract.external_id,
        code: billable_metric.code, timestamp: Time.zone.parse(day))
    end
  end

  before do
    travel_to(now)
    create(:contract_rate_card, organization:, contract:, rate_card:, billing_scope:,
      effective_date: Date.new(2027, 1, 1), billing_anchor_date: Date.new(2027, 1, 1))
    alert
    allow(Contracts::CurrentUsageService).to receive(:call!).and_call_original
  end

  # The start of a window, as the alert stores it in the customer's timezone
  def window(started_at, value)
    {"started_at" => Time.zone.parse(started_at).strftime("%Y-%m-%dT%H:%M:%S.%6N"), "value" => BigDecimal(value).to_s("F")}
  end

  def contract_activity_kept?
    UsageMonitoring::ContractActivity.exists?(contract_activity.id)
  end

  it "triggers every threshold the usage is already past, from 0, at the first evaluation (B1)" do
    expect(result).to be_success

    triggered = alert.all_triggered_alerts.sole
    expect(triggered).to have_attributes(
      kind: "triggered",
      contract:,
      previous_value: 0,
      current_value: 2, # the Feb 3 and Feb 5 events: the Jan 10 one is in the closed window
      triggered_at: now
    )
    expect(triggered.crossed_thresholds).to eq([
      {"code" => "warn1", "value" => "1.0", "recurring" => false},
      {"code" => "warn2", "value" => "2.0", "recurring" => false}
    ])
    expect(SendWebhookJob).to have_been_enqueued.once.with("alert.triggered", triggered)
    expect(alert.reload).to have_attributes(
      previous_value: 2,
      previous_windows: {product.id => window("2027-02-01", 2)},
      last_processed_at: now
    )
  end

  it "deletes the contract activity" do
    expect(result).to be_success
    expect(contract_activity_kept?).to be(false)
  end

  context "with several alerts on the contract" do
    let(:amount_alert) do
      create(:contract_usage_amount_alert, organization:, contract_external_id: contract.external_id, thresholds: [300])
    end

    before { amount_alert }

    it "evaluates them all on one usage read, before taxes" do
      expect(result).to be_success

      expect(Contracts::CurrentUsageService).to have_received(:call!).once
      expect(Contracts::CurrentUsageService).to have_received(:call!).with(contract:, timestamp: now, apply_taxes: false)
      expect(alert.reload).to have_attributes(previous_value: 2, last_processed_at: now)
      expect(amount_alert.reload).to have_attributes(previous_value: 400, last_processed_at: now) # 2 February events at 2 EUR
      expect(SendWebhookJob).to have_been_enqueued.once.with("alert.triggered", alert.all_triggered_alerts.sole)
      expect(SendWebhookJob).to have_been_enqueued.once.with("alert.triggered", amount_alert.all_triggered_alerts.sole)
    end
  end

  context "when the usage read ends after a renewal it started before" do
    let(:now) { Time.zone.parse("2027-01-31 23:59:59") }

    before do
      allow(Contracts::CurrentUsageService).to receive(:call!).and_wrap_original do |method, **args|
        travel(2.seconds)
        method.call(**args)
      end
    end

    it "prices the window open when the read started, and stamps the alert with that instant" do
      expect(result).to be_success

      expect(Contracts::CurrentUsageService).to have_received(:call!).with(contract:, timestamp: now, apply_taxes: false)
      expect(alert.all_triggered_alerts.sole).to have_attributes(
        current_value: 1, # the Jan 10 event, in the January window
        triggered_at: now + 2.seconds
      )
      expect(alert.reload).to have_attributes(
        previous_value: 1,
        previous_windows: {product.id => window("2027-01-01", 1)},
        last_processed_at: now
      )
    end
  end

  context "when two activity jobs evaluate the contract" do
    let(:next_contract_activity) { create(:contract_activity, organization:, contract:, enqueued: true) }

    context "with a February 4 rate change between evaluations" do
      before do
        create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2027-02-04"),
          rate_properties: {"amount" => "5"})
        travel_to(Time.zone.parse("2027-02-03 12:00:00"))
        described_class.call!(contract_activity:)
        travel_to(now)
      end

      it "keeps the cycle baseline and crosses the second threshold" do
        described_class.call!(contract_activity: next_contract_activity)

        trigger = alert.triggered_alerts.find_by!(triggered_at: now)
        expect(trigger).to have_attributes(previous_value: 1, current_value: 2)
        expect(trigger.crossed_thresholds.pluck("code")).to eq(["warn2"])
        expect(alert.reload.previous_windows).to eq(product.id => window("2027-02-01", 2))
      end

      context "with segment billing" do
        let(:billing_scope) { :segment }

        it "resets the baseline and crosses the first threshold again" do
          described_class.call!(contract_activity: next_contract_activity)

          trigger = alert.triggered_alerts.find_by!(triggered_at: now)
          expect(trigger).to have_attributes(previous_value: 0, current_value: 1)
          expect(trigger.crossed_thresholds.pluck("code")).to eq(["warn1"])
          expect(alert.reload.previous_windows).to eq(product.id => window("2027-02-04", 1))
        end
      end
    end

    it "sends one webhook for the crossing (B6)" do
      described_class.call!(contract_activity:)
      travel(1.minute)
      described_class.call!(contract_activity: next_contract_activity)

      triggered = alert.all_triggered_alerts.sole
      expect(SendWebhookJob).to have_been_enqueued.once.with("alert.triggered", triggered)
      expect(alert.reload).to have_attributes(previous_value: 2, last_processed_at: now + 1.minute)
    end

    context "when the job that measured first finishes last" do
      it "skips its older usage and sends one webhook for the crossing (B6)" do
        travel(1.minute)
        described_class.call!(contract_activity: next_contract_activity)
        travel_to(now)
        described_class.call!(contract_activity:)

        triggered = alert.all_triggered_alerts.sole
        expect(triggered.triggered_at).to eq(now + 1.minute)
        expect(SendWebhookJob).to have_been_enqueued.once.with("alert.triggered", triggered)
        expect(alert.reload).to have_attributes(previous_value: 2, last_processed_at: now + 1.minute)
      end
    end
  end

  context "with alerts of other contracts" do
    let(:other_contract_alert) { create(:contract_usage_units_alert, organization:, product:, thresholds: [1]) }
    let(:other_organization_alert) do
      other_organization = create(:organization, feature_flags: %w[product_catalog contract_alerts])
      create(:contract_usage_amount_alert, organization: other_organization, contract_external_id: contract.external_id, thresholds: [1])
    end

    before do
      other_contract_alert
      other_organization_alert
    end

    it "evaluates only the alerts of the contract" do
      expect(result).to be_success

      expect(alert.reload.last_processed_at).to eq(now)
      [other_contract_alert, other_organization_alert].each do |other_alert|
        expect(other_alert.reload).to have_attributes(previous_value: 0, previous_windows: {}, last_processed_at: nil)
        expect(other_alert.all_triggered_alerts).to be_empty
      end
    end
  end

  %i[draft pending terminated canceled].each do |status|
    context "when the contract is #{status}" do
      let(:inactive_contract) { create(:contract, status, organization:, customer:) }
      let(:contract_activity) { create(:contract_activity, organization:, contract: inactive_contract, enqueued: true) }
      let(:alert) do
        create(:contract_usage_units_alert, organization:, contract_external_id: inactive_contract.external_id, product:, thresholds: [1])
      end

      it "deletes the contract activity without evaluating the alerts, which stay" do
        expect(result).to be_success

        expect(contract_activity_kept?).to be(false)
        expect(Contracts::CurrentUsageService).not_to have_received(:call!)
        expect(alert.reload).to have_attributes(deleted_at: nil, previous_value: 0, last_processed_at: nil)
      end
    end
  end

  context "when the contract has no alert" do
    let(:alert) { nil }

    it "deletes the contract activity without reading the usage" do
      expect(result).to be_success

      expect(contract_activity_kept?).to be(false)
      expect(Contracts::CurrentUsageService).not_to have_received(:call!)
    end
  end

  context "when the only alert of the contract is deleted" do
    before { alert.discard! }

    it "deletes the contract activity without reading the usage" do
      expect(result).to be_success

      expect(contract_activity_kept?).to be(false)
      expect(Contracts::CurrentUsageService).not_to have_received(:call!)
      expect(alert.reload).to have_attributes(previous_value: 0, last_processed_at: nil)
    end
  end

  context "when the evaluation of an alert fails" do
    let(:failing_alert) do
      create(:contract_usage_amount_alert, organization:, contract_external_id: contract.external_id, thresholds: [300])
    end

    before do
      failing_alert
      allow(UsageMonitoring::ProcessAlertService).to receive(:call!).and_wrap_original do |method, **args|
        raise ActiveRecord::LockWaitTimeout if args[:alert] == failing_alert

        method.call(**args)
      end
    end

    it "evaluates the other alerts, deletes the contract activity and raises the error" do
      expect { result }.to raise_error(ActiveRecord::LockWaitTimeout)

      expect(alert.reload).to have_attributes(previous_value: 2, last_processed_at: now)
      expect(SendWebhookJob).to have_been_enqueued.once.with("alert.triggered", alert.all_triggered_alerts.sole)
      expect(failing_alert.reload).to have_attributes(previous_value: 0, last_processed_at: nil)
      expect(contract_activity_kept?).to be(false)
    end
  end

  context "when the usage cannot be read" do
    before { allow(Contracts::CurrentUsageService).to receive(:call!).and_raise(ActiveRecord::QueryCanceled) }

    it "evaluates nothing, deletes the contract activity and raises the error, as for subscriptions" do
      expect { result }.to raise_error(ActiveRecord::QueryCanceled)

      expect(alert.reload).to have_attributes(previous_value: 0, last_processed_at: nil)
      expect(alert.all_triggered_alerts).to be_empty
      expect(contract_activity_kept?).to be(false)
    end

    it "lets the next wake-up track the contract again" do
      expect { result }.to raise_error(ActiveRecord::QueryCanceled)

      expect { UsageMonitoring::TrackContractActivityService.call(contract:) }
        .to change(UsageMonitoring::ContractActivity, :count).by(1)
    end
  end
end
