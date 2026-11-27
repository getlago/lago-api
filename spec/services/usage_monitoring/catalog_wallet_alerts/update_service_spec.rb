# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::CatalogWalletAlerts::UpdateService do
  subject(:result) { described_class.call(alert:, params:) }

  # A let, not a let_it_be: a before_all holds the group in one transaction on a connection that every thread then
  # shares, so the races below would wait on each other in Ruby instead of on the database
  let(:organization) { create(:organization) }

  let(:alert) { create(:plan_wallet_alert, organization:, alert_type: "balance", code: "low_balance", name: "Low balance") }
  let(:params) { {name: "Running low", thresholds: [{code: "low", value: "5000"}, {value: "0"}]} }

  # Through the alert's own association, which holds a template's thresholds as well as a contract wallet alert's
  before { alert.thresholds.create!(organization:, code: "low", value: 10_000, notify_on: %w[triggered resolved]) }

  it "updates the name and replaces the thresholds, keeping the notify_on of a threshold by its code" do
    expect(result).to be_success
    expect(result.alert).to eq(alert)
    expect(alert.reload.name).to eq("Running low")
    expect(alert.thresholds.order(:value).pluck(:code, :value, :notify_on)).to eq([
      [nil, 0, %w[triggered]],
      ["low", 5000, %w[triggered resolved]]
    ])
  end

  context "with only a name" do
    let(:params) { {name: "Running low"} }

    it "keeps the thresholds" do
      expect(result).to be_success
      expect(alert.reload.thresholds.pluck(:code, :value)).to eq([["low", 10_000]])
    end
  end

  context "with only thresholds" do
    let(:params) { {thresholds: [{value: "100"}]} }

    it "keeps the name and dates the template" do
      travel_to(1.day.from_now) do
        expect(result).to be_success
        expect(alert.reload).to have_attributes(name: "Low balance", updated_at: Time.current)
        expect(alert.thresholds.pluck(:value)).to eq([100])
      end
    end
  end

  context "with the code or the alert type" do
    let(:params) { {code: "other", alert_type: "ongoing_balance"} }

    it "refuses both" do
      expect(result).to be_failure
      expect(result.error.messages).to eq({code: ["value_cannot_be_changed"], alert_type: ["value_cannot_be_changed"]})
    end
  end

  context "with a fraction of a cent" do
    let(:params) { {thresholds: [{value: "100.5"}]} }

    it "fails and keeps the thresholds" do
      expect(result).to be_failure
      expect(result.error.messages).to eq({"thresholds[0].value": ["value_is_invalid"]})
      expect(alert.reload.thresholds.pluck(:value)).to eq([10_000])
    end
  end

  context "with a name that is a list" do
    let(:params) { {name: ["Running low"]} }

    it "fails and keeps the name" do
      expect(result).to be_failure
      expect(result.error.messages).to eq({name: ["value_is_invalid"]})
      expect(alert.reload.name).to eq("Low balance")
    end
  end

  context "with an empty list of thresholds" do
    let(:params) { {thresholds: []} }

    it "fails and keeps the thresholds" do
      expect(result).to be_failure
      expect(result.error.messages).to eq({thresholds: ["value_is_mandatory"]})
      expect(alert.reload.thresholds.pluck(:value)).to eq([10_000])
    end
  end

  context "with a negative threshold on a balance alert" do
    let(:params) { {thresholds: [{value: "-100"}]} }

    it "fails" do
      expect(result).to be_failure
      expect(result.error.messages).to eq({"thresholds[0].value": ["value_is_invalid"]})
    end
  end

  context "with a recurring step on its own on a balance alert" do
    # Its first line sits one step below 0, which a balance never reaches
    let(:params) { {thresholds: [{value: "5000", recurring: true}]} }

    it "fails and keeps the thresholds" do
      expect(result).to be_failure
      expect(result.error.messages).to eq({"thresholds[0].value": ["value_is_invalid"]})
      expect(alert.reload.thresholds.pluck(:value)).to eq([10_000])
    end
  end

  context "when a threshold cannot be saved" do
    # The controller keeps only the threshold fields, so only a direct caller can send this one
    let(:params) { {name: "Running low", thresholds: [{value: "100", organization_id: nil}]} }

    it "fails and keeps the name and the thresholds" do
      expect(result).to be_failure
      expect(result.error.messages).to eq({organization: ["relation_must_exist"]})
      expect(alert.reload.name).to eq("Low balance")
      expect(alert.thresholds.pluck(:value)).to eq([10_000])
    end
  end

  context "with a negative threshold on an ongoing balance alert" do
    let(:alert) { create(:plan_wallet_alert, organization:, alert_type: "ongoing_balance", code: "low_balance", name: "Low balance") }
    let(:params) { {thresholds: [{value: "-100"}]} }

    it "accepts it, since unbilled usage can take the ongoing balance below 0" do
      expect(result).to be_success
      expect(alert.reload.thresholds.pluck(:value)).to eq([-100])
    end
  end

  context "without an alert" do
    subject(:result) { described_class.call(alert: nil, params:) }

    it "fails" do
      expect(result).to be_failure
      expect(result.error.error_code).to eq("alert_not_found")
    end
  end

  context "when another request renamed the template after this one loaded it" do
    let(:params) { {name: "Low balance"} }

    before { UsageMonitoring::PlanWalletAlert.find(alert.id).update!(name: "Renamed elsewhere") }

    it "saves the name it was asked for" do
      expect(result).to be_success
      expect(alert.reload.name).to eq("Low balance")
    end
  end

  context "when the alert was deleted before the lock" do
    before { UsageMonitoring::PlanWalletAlert.find(alert.id).destroy! }

    it "fails" do
      expect(result).to be_failure
      expect(result.error.error_code).to eq("alert_not_found")
    end
  end

  context "when the plan wallet was deleted before the lock" do
    before { PlanWallet.find(alert.plan_wallet_id).discard! }

    it "fails and keeps the template as it was" do
      expect(result).to be_failure
      expect(result.error.error_code).to eq("plan_wallet_not_found")
      expect(alert.reload.name).to eq("Low balance")
    end
  end

  context "with an alert on a contract wallet" do
    let(:customer) { create(:customer, organization:) }
    let(:contract) { create(:contract, :pending, customer:) }
    let(:catalog_wallet) { create(:catalog_wallet, organization:, customer:, contract:) }
    let(:alert) { create(:catalog_wallet_alert, organization:, catalog_wallet:, alert_type: "balance", code: "low_balance", name: "Low balance") }

    context "when the alert is watching the balance" do
      let(:contract) { create(:contract, customer:) }
      let(:catalog_wallet) { create(:catalog_wallet, organization:, customer:, contract:, balance_cents: 1_500) }
      let(:alert) { create(:catalog_wallet_alert, organization:, catalog_wallet:, alert_type: "balance", code: "low_balance", previous_value: 1_500, last_processed_at: 1.hour.ago) }
      let(:params) { {thresholds: [{code: "warning", value: "2000", notify_on: %w[triggered resolved]}, {code: "low", value: "1000", notify_on: %w[triggered resolved]}]} }

      it "seeds the opted-in line the edit puts in alarm and sends nothing" do
        expect { result }.not_to have_enqueued_job(SendWebhookJob)

        expect(result).to be_success
        # 2000 is above the balance of 1500, so it is in alarm; 1000 is below it
        seeded = alert.all_triggered_alerts.sole
        expect(seeded).to have_attributes(kind: "seeded", catalog_wallet:, current_value: 1_500, previous_value: 1_500)
        expect(seeded.crossed_thresholds).to eq([{"code" => "warning", "value" => "2000.0", "recurring" => false}])
      end

      context "when the line it moves out of alarm had been recorded" do
        # "low" was at 10000, in alarm at 1500, and moves to 1000, out of alarm
        before { create(:catalog_wallet_triggered_alert, organization:, alert:, kind: :seeded, current_value: 1_500, previous_value: 1_500, crossed_thresholds: [{code: "low", value: BigDecimal(10_000), recurring: false}]) }

        it "resolves it with threshold_updated and sends alert.resolved" do
          expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("alert.resolved", instance_of(UsageMonitoring::CatalogWalletTriggeredAlert))

          # "warning" at 2000 stays in alarm at 1500, so the alert is not fully resolved
          resolved = alert.all_triggered_alerts.resolved.sole
          expect(resolved).to have_attributes(
            resolution_reason: "threshold_updated",
            current_value: 1_500,
            previous_value: 1_500,
            in_alarm_thresholds: ["warning"],
            fully_resolved: false,
            catalog_wallet:
          )
          expect(resolved.crossed_thresholds).to eq([{"code" => "low", "value" => "10000.0", "recurring" => false}])
        end

        context "when the line moves but stays in alarm" do
          # 5000 is still above the balance of 1500
          let(:params) { {thresholds: [{code: "warning", value: "2000", notify_on: %w[triggered resolved]}, {code: "low", value: "5000", notify_on: %w[triggered resolved]}]} }

          it "resolves nothing and sends nothing" do
            expect { result }.not_to have_enqueued_job(SendWebhookJob)

            expect(alert.all_triggered_alerts.resolved).to be_empty
          end
        end

        context "when the line leaves alarm but is opted out of resolutions" do
          let(:params) { {thresholds: [{code: "warning", value: "2000", notify_on: %w[triggered resolved]}, {code: "low", value: "1000", notify_on: %w[triggered]}]} }

          it "resolves nothing and sends nothing" do
            expect { result }.not_to have_enqueued_job(SendWebhookJob)

            expect(alert.all_triggered_alerts.resolved).to be_empty
          end
        end
      end

      context "when the edit removes a recorded line" do
        let(:params) { {thresholds: [{code: "warning", value: "2000", notify_on: %w[triggered resolved]}]} }

        before { create(:catalog_wallet_triggered_alert, organization:, alert:, kind: :seeded, current_value: 1_500, previous_value: 1_500, crossed_thresholds: [{code: "low", value: BigDecimal(10_000), recurring: false}]) }

        it "resolves it with threshold_removed and sends alert.resolved" do
          expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("alert.resolved", instance_of(UsageMonitoring::CatalogWalletTriggeredAlert))

          resolved = alert.all_triggered_alerts.resolved.sole
          expect(resolved).to have_attributes(
            resolution_reason: "threshold_removed",
            current_value: 1_500,
            previous_value: 1_500,
            in_alarm_thresholds: ["warning"],
            fully_resolved: false,
            catalog_wallet:
          )
          expect(resolved.crossed_thresholds).to eq([{"code" => "low", "value" => "10000.0", "recurring" => false}])
        end

        context "when the wallet was emptied since the alert was last observed" do
          # An empty wallet seeds nothing, but the edit still closes the alarm of the line it removes
          let(:catalog_wallet) { create(:catalog_wallet, organization:, customer:, contract:, balance_cents: 0) }

          it "resolves it all the same and seeds nothing more" do
            expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("alert.resolved", instance_of(UsageMonitoring::CatalogWalletTriggeredAlert))

            expect(alert.all_triggered_alerts.resolved.sole.resolution_reason).to eq("threshold_removed")
            expect(alert.all_triggered_alerts.seeded.count).to eq(1)
          end
        end
      end

      context "when a balance change is in flight", transaction: false do
        # 5000 is in alarm at the 1500 the wallet holds before the change, not at the 8000 it leaves; 10000 is at both
        let(:params) do
          {thresholds: [{code: "high", value: "5000", notify_on: %w[triggered resolved]}, {code: "top", value: "10000", notify_on: %w[triggered resolved]}]}
        end

        it "waits for it and seeds from the balance it leaves" do
          locked = Queue.new
          release = Queue.new

          writer = Thread.new do
            ApplicationRecord.connection_pool.with_connection do
              ApplicationRecord.transaction do
                CatalogWallet.find(catalog_wallet.id).update!(balance_cents: 8_000)
                locked << true
                release.pop
              end
            end
          end
          begin
            Timeout.timeout(10) { locked.pop }

            editor = Thread.new do
              ApplicationRecord.connection_pool.with_connection { described_class.call(alert: UsageMonitoring::CatalogWalletAlert.find(alert.id), params:) }
            end
            Timeout.timeout(10) { sleep(0.01) until lock_waits.positive? }
          ensure
            release << true
          end
          Timeout.timeout(10) { writer.join }

          expect(Timeout.timeout(10) { editor.value }).to be_success
          expect(alert.all_triggered_alerts.sole.crossed_thresholds.pluck("code")).to eq(["top"])
        end
      end
    end

    context "when an ongoing balance alert started on an empty wallet" do
      let(:contract) { create(:contract, customer:) }
      let(:alert) { create(:catalog_wallet_alert, organization:, catalog_wallet:, alert_type: "ongoing_balance", code: "low_ongoing_balance", previous_value: 0, last_processed_at: 1.hour.ago) }
      # The same line as before, opted in and in alarm at 0
      let(:params) { {thresholds: [{code: "low", value: "10000", notify_on: %w[triggered resolved]}]} }

      it "seeds nothing, as its baseline did" do
        expect(result).to be_success
        expect(alert.all_triggered_alerts).to be_empty
      end

      context "when money reached the wallet before the next evaluation" do
        let(:catalog_wallet) { create(:catalog_wallet, organization:, customer:, contract:, balance_cents: 1_500, ongoing_balance_cents: 1_500, last_ongoing_balance_sync_at: 1.hour.ago) }
        let(:params) { {thresholds: [{code: "mid", value: "1000", notify_on: %w[triggered resolved]}, {code: "low", value: "10000", notify_on: %w[triggered resolved]}]} }

        it "seeds only the line still in alarm at the new value" do
          expect(result).to be_success
          # 1000 is in alarm at 0 but not at 1500: the evaluation recovers it. 10000 is in alarm at both, as a create would seed it
          expect(alert.all_triggered_alerts.sole.crossed_thresholds.pluck("code")).to eq(["low"])
        end
      end
    end

    context "when the balance went down since the alert was last observed" do
      let(:contract) { create(:contract, customer:) }
      let(:catalog_wallet) { create(:catalog_wallet, organization:, customer:, contract:, balance_cents: 600) }
      let(:alert) { create(:catalog_wallet_alert, organization:, catalog_wallet:, alert_type: "balance", code: "low_balance", previous_value: 800, last_processed_at: 1.hour.ago) }
      let(:params) { {thresholds: [{code: "high", value: "1000", notify_on: %w[triggered resolved]}, {code: "mid", value: "700", notify_on: %w[triggered resolved]}]} }

      it "seeds the line in alarm at both values and leaves the one the evaluation crosses" do
        expect(result).to be_success
        # 1000 is in alarm at 800 and at 600. 700 is only at 600, so the next evaluation crosses it and announces it
        expect(alert.all_triggered_alerts.sole.crossed_thresholds.pluck("code")).to eq(["high"])
      end
    end

    context "when an ongoing balance alert watches a funded wallet whose ongoing balance is below 0" do
      let(:contract) { create(:contract, customer:) }
      let(:catalog_wallet) { create(:catalog_wallet, organization:, customer:, contract:, balance_cents: 1_500, ongoing_balance_cents: -500, last_ongoing_balance_sync_at: 1.hour.ago) }
      let(:alert) { create(:catalog_wallet_alert, organization:, catalog_wallet:, alert_type: "ongoing_balance", code: "low_ongoing_balance", previous_value: -500, last_processed_at: 1.hour.ago) }
      let(:params) { {thresholds: [{code: "zero", value: "0", notify_on: %w[triggered resolved]}]} }

      it "seeds the line the edit puts in alarm, as a create on that wallet would" do
        expect(result).to be_success
        seeded = alert.all_triggered_alerts.sole
        expect(seeded).to have_attributes(kind: "seeded", current_value: -500, previous_value: -500)
        expect(seeded.crossed_thresholds).to eq([{"code" => "zero", "value" => "0.0", "recurring" => false}])
      end

      context "when the ongoing balance is 0" do
        let(:catalog_wallet) { create(:catalog_wallet, organization:, customer:, contract:, balance_cents: 500, ongoing_balance_cents: 0, last_ongoing_balance_sync_at: 1.hour.ago) }
        let(:alert) { create(:catalog_wallet_alert, organization:, catalog_wallet:, alert_type: "ongoing_balance", code: "low_ongoing_balance", previous_value: 0, last_processed_at: 1.hour.ago) }

        it "seeds the line too" do
          expect(result).to be_success
          expect(alert.all_triggered_alerts.sole.crossed_thresholds.pluck("code")).to eq(["zero"])
        end
      end

      context "when the wallet's ongoing balance was never computed" do
        let(:catalog_wallet) { create(:catalog_wallet, organization:, customer:, contract:, balance_cents: 1_500) }

        it "reads the balance, where the new line is not in alarm, and seeds nothing" do
          expect(result).to be_success
          expect(alert.thresholds.pluck(:code)).to eq(["zero"])
          # At the column's 0 the line would be in alarm and seeded
          expect(alert.all_triggered_alerts).to be_empty
        end
      end
    end

    # Created while the contract was pending: nothing starts it when money arrives yet
    context "when a balance alert has no baseline on a funded wallet" do
      let(:contract) { create(:contract, customer:) }
      let(:catalog_wallet) { create(:catalog_wallet, organization:, customer:, contract:, balance_cents: 1_500) }
      let(:params) { {thresholds: [{code: "warning", value: "2000", notify_on: %w[triggered resolved]}]} }

      it "changes the thresholds and seeds nothing" do
        expect(result).to be_success
        expect(alert.reload.previous_value).to be_nil
        expect(alert.all_triggered_alerts).to be_empty
      end
    end

    it "updates the name and replaces the thresholds, recording and sending nothing" do
      expect { result }.not_to have_enqueued_job(SendWebhookJob)

      expect(result).to be_success
      expect(result.alert).to eq(alert)
      expect(alert.reload).to have_attributes(name: "Running low", previous_value: nil, last_processed_at: nil)
      expect(alert.thresholds.order(:value).pluck(:code, :value, :notify_on)).to eq([
        [nil, 0, %w[triggered]],
        ["low", 5000, %w[triggered resolved]]
      ])
      expect(alert.all_triggered_alerts).to be_empty
    end

    context "when the contract is active" do
      let(:contract) { create(:contract, customer:) }

      it "updates the alert" do
        expect(result).to be_success
        expect(alert.reload.name).to eq("Running low")
      end
    end

    context "when the wallet has ended" do
      let(:catalog_wallet) { create(:catalog_wallet, organization:, customer:, contract:, terminated_at: Time.current) }

      it "refuses the write and keeps the alert as it was" do
        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("wallet_alerts_read_only")
        expect(alert.reload.name).to eq("Low balance")
        expect(alert.thresholds.pluck(:value)).to eq([10_000])
      end
    end

    context "when the contract was canceled after the alert was loaded" do
      before { Contracts::TerminateService.call!(contract: Contract.find(contract.id)) }

      it "refuses the write" do
        expect(result).to be_failure
        expect(result.error.code).to eq("contract_not_live")
      end
    end

    context "when the wallet was deleted before the lock" do
      before { CatalogWallet.find(catalog_wallet.id).discard! }

      it "fails and keeps the alert as it was" do
        expect(result).to be_failure
        expect(result.error.error_code).to eq("contract_wallet_not_found")
        expect(alert.reload.name).to eq("Low balance")
      end
    end

    context "when the alert was deleted before the lock" do
      before { UsageMonitoring::CatalogWalletAlert.find(alert.id).destroy! }

      it "fails" do
        expect(result).to be_failure
        expect(result.error.error_code).to eq("alert_not_found")
      end
    end
  end
end
