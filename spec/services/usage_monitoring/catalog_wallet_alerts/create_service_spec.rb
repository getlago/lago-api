# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::CatalogWalletAlerts::CreateService do
  subject(:result) { described_class.call(plan_wallet:, params:) }

  # Lets, not let_it_be: a before_all would make the threads of the race below share one connection
  let(:organization) { create(:organization) }
  let(:plan_wallet) { create(:plan_wallet, organization:) }

  let(:params) do
    {
      alert_type: "balance",
      code: "low_balance",
      name: "Low balance",
      thresholds: [
        {code: "low", value: "10000", notify_on: %w[triggered resolved]},
        {code: "empty", value: "0"}
      ]
    }
  end

  it "creates the template and its thresholds" do
    expect(result).to be_success
    expect(result.alert).to be_persisted
    expect(result.alert).to have_attributes(organization:, plan_wallet:, alert_type: "balance", code: "low_balance", name: "Low balance")
    expect(result.alert.thresholds.order(:value).pluck(:organization_id, :code, :value, :recurring, :notify_on)).to eq([
      [organization.id, "empty", 0, false, %w[triggered]],
      [organization.id, "low", 10_000, false, %w[triggered resolved]]
    ])
  end

  context "with a recurring threshold" do
    before { params[:thresholds] = [{code: "low", value: "10000"}, {code: "every_50", value: 5000, recurring: true}] }

    it "creates it" do
      expect(result).to be_success
      expect(result.alert.thresholds.find_by(recurring: true)).to have_attributes(code: "every_50", value: 5000)
    end
  end

  context "with a recurring step whose first line is 0" do
    before { params[:thresholds] = [{value: "5000"}, {value: "5000", recurring: true}] }

    it "creates it, since an empty wallet reaches that line" do
      expect(result).to be_success
    end
  end

  context "with a recurring step on its own" do
    # Its first line sits one step below 0, which a balance never reaches
    before { params[:thresholds] = [{value: "5000", recurring: true}] }

    it "fails on its value and creates nothing" do
      expect(result).to be_failure
      expect(result.error.messages).to eq({"thresholds[0].value": ["value_is_invalid"]})
      expect(plan_wallet.alerts).to be_empty
    end
  end

  context "with a recurring step larger than the lowest threshold" do
    # Its first line is 1000 - 5000 = -4000
    before { params[:thresholds] = [{value: "1000"}, {value: "5000", recurring: true}] }

    it "fails on the recurring step's value and creates nothing" do
      expect(result).to be_failure
      expect(result.error.messages).to eq({"thresholds[1].value": ["value_is_invalid"]})
      expect(plan_wallet.alerts).to be_empty
    end
  end

  context "with a recurring step larger than the lowest of several thresholds" do
    # Its first line is min(10000, 1000) - 5000 = -4000
    before { params[:thresholds] = [{value: "10000"}, {value: "1000"}, {value: "5000", recurring: true}] }

    it "fails on the recurring step's value" do
      expect(result.error.messages).to eq({"thresholds[2].value": ["value_is_invalid"]})
    end
  end

  context "with a negative threshold that also takes the recurring step below 0" do
    before { params[:thresholds] = [{value: "-100"}, {value: "50", recurring: true}] }

    it "fails on the negative threshold's value" do
      expect(result.error.messages).to eq({"thresholds[0].value": ["value_is_invalid"]})
    end
  end

  context "with a recurring step on its own on an ongoing balance alert" do
    before { params.merge!(alert_type: "ongoing_balance", thresholds: [{value: "5000", recurring: true}]) }

    it "creates it, since unbilled usage can take the ongoing balance below 0" do
      expect(result).to be_success
    end
  end

  context "without a wallet" do
    let(:plan_wallet) { nil }

    it "fails" do
      expect(result).to be_failure
      expect(result.error.error_code).to eq("wallet_not_found")
    end
  end

  context "when the plan wallet was deleted before the lock" do
    # Another request deletes it: the instance the service holds stays kept until the lock reloads it
    before { PlanWallet.find(plan_wallet.id).discard! }

    it "fails and writes nothing on it" do
      expect(result).to be_failure
      expect(result.error.error_code).to eq("plan_wallet_not_found")
      expect(UsageMonitoring::PlanWalletAlert.where(plan_wallet_id: plan_wallet.id)).to be_empty
    end
  end

  context "without an alert type" do
    before { params.delete(:alert_type) }

    it "fails" do
      expect(result).to be_failure
      expect(result.error.messages).to eq({alert_type: ["value_is_mandatory"]})
    end
  end

  context "with an unknown alert type" do
    before { params[:alert_type] = "usage_amount" }

    it "fails" do
      expect(result).to be_failure
      expect(result.error.messages).to eq({alert_type: ["invalid_type"]})
    end
  end

  context "without thresholds" do
    before { params[:thresholds] = [] }

    it "fails with the shared threshold checks" do
      expect(result).to be_failure
      expect(result.error.messages).to eq({thresholds: ["value_is_mandatory"]})
    end
  end

  context "with fractions of a cent" do
    before { params[:thresholds] = [{value: "10000"}, {value: "10000.5"}, {value: "20000.5"}] }

    it "fails on the first one's value and creates nothing" do
      expect(result).to be_failure
      expect(result.error.messages).to eq({"thresholds[1].value": ["value_is_invalid"]})
      expect(plan_wallet.alerts).to be_empty
    end
  end

  context "with a whole number of cents written as a decimal" do
    before { params[:thresholds] = [{value: "10000.0"}] }

    it "creates the threshold" do
      expect(result).to be_success
      expect(result.alert.thresholds.sole.value).to eq(10_000)
    end
  end

  context "with negative balance thresholds" do
    before { params[:thresholds] = [{value: "10000"}, {value: "-100"}, {value: "-200"}] }

    it "fails on the first one's value and creates nothing" do
      expect(result).to be_failure
      expect(result.error.messages).to eq({"thresholds[1].value": ["value_is_invalid"]})
      expect(plan_wallet.alerts).to be_empty
    end
  end

  context "with a negative ongoing balance threshold" do
    before { params.merge!(alert_type: "ongoing_balance", thresholds: [{value: "-100"}]) }

    it "creates it, since unbilled usage can take the ongoing balance below 0" do
      expect(result).to be_success
      expect(result.alert.thresholds.sole.value).to eq(-100)
    end
  end

  {code: ["low_balance"], name: {text: "Low balance"}}.each do |field, value|
    context "with a #{field} that is not a single value" do
      before { params[field] = value }

      it "fails on it and creates nothing" do
        expect(result).to be_failure
        expect(result.error.messages).to eq({field => ["value_is_invalid"]})
        expect(plan_wallet.alerts).to be_empty
      end
    end
  end

  context "with a code that cannot address the alert in its route" do
    before { params[:code] = "low balance" }

    it "fails" do
      expect(result).to be_failure
      expect(result.error.messages).to eq({code: ["value_is_invalid"]})
    end
  end

  context "when the wallet already has an alert of that type" do
    before { create(:plan_wallet_alert, plan_wallet:, organization:, alert_type: "balance", code: "other") }

    it "fails on the type index" do
      expect(result).to be_failure
      expect(result.error.messages).to eq({base: ["alert_already_exists"]})
    end
  end

  context "when the wallet already has an alert with that code" do
    before { create(:plan_wallet_alert, plan_wallet:, organization:, alert_type: "ongoing_balance", code: "low_balance") }

    it "fails on the code index" do
      expect(result).to be_failure
      expect(result.error.messages).to eq({code: ["value_already_exist"]})
    end
  end

  context "with a contract wallet" do
    subject(:result) { described_class.call(catalog_wallet:, params:) }

    let(:customer) { create(:customer, organization:) }
    let(:contract) { create(:contract, :pending, customer:) }
    let(:catalog_wallet) { create(:catalog_wallet, organization:, customer:, contract:) }

    it "creates the alert and its thresholds, with no previous value, and sends nothing" do
      expect { result }.not_to have_enqueued_job(SendWebhookJob)

      expect(result).to be_success
      expect(result.alert).to be_a(UsageMonitoring::CatalogWalletAlert)
      expect(result.alert).to have_attributes(
        organization:,
        catalog_wallet:,
        alert_type: "balance",
        code: "low_balance",
        name: "Low balance",
        previous_value: nil,
        last_processed_at: nil
      )
      expect(result.alert.thresholds.order(:value).pluck(:organization_id, :code, :value, :recurring, :notify_on)).to eq([
        [organization.id, "empty", 0, false, %w[triggered]],
        [organization.id, "low", 10_000, false, %w[triggered resolved]]
      ])
      expect(result.alert.all_triggered_alerts).to be_empty
    end

    context "when the contract is active" do
      let(:contract) { create(:contract, customer:) }
      let(:catalog_wallet) { create(:catalog_wallet, organization:, customer:, contract:, balance_cents: 1_500) }

      before { params[:thresholds] = [{code: "warning", value: "2000", notify_on: %w[triggered resolved]}] }

      it "watches at once from the balance, seeding the line already past and sending nothing" do
        freeze_time do
          expect { result }.not_to have_enqueued_job(SendWebhookJob)

          expect(result).to be_success
          expect(result.alert).to have_attributes(previous_value: 1_500, last_processed_at: Time.current)
          seeded = result.alert.all_triggered_alerts.sole
          expect(seeded).to have_attributes(kind: "seeded", current_value: 1_500, previous_value: 1_500)
          expect(seeded.crossed_thresholds).to eq([{"code" => "warning", "value" => "2000.0", "recurring" => false}])
        end
      end

      context "when the wallet is empty" do
        let(:catalog_wallet) { create(:catalog_wallet, organization:, customer:, contract:) }

        it "creates a balance alert that waits for money" do
          expect(result).to be_success
          expect(result.alert).to have_attributes(previous_value: nil, last_processed_at: nil)
          expect(result.alert.all_triggered_alerts).to be_empty
        end

        context "with an ongoing balance alert" do
          let(:catalog_wallet) { create(:catalog_wallet, organization:, customer:, contract:, last_ongoing_balance_sync_at: 1.hour.ago) }

          before { params.merge!(alert_type: "ongoing_balance", thresholds: [{code: "empty", value: "0", notify_on: %w[triggered resolved]}]) }

          it "watches at once from 0 and seeds nothing" do
            expect(result).to be_success
            expect(result.alert.previous_value).to eq(0)
            expect(result.alert.all_triggered_alerts).to be_empty
          end
        end
      end

      context "with an ongoing balance alert on a wallet whose ongoing balance was never computed" do
        before do
          params.merge!(alert_type: "ongoing_balance", thresholds: [
            {code: "warning", value: "2000", notify_on: %w[triggered resolved]},
            {code: "empty", value: "0", notify_on: %w[triggered resolved]}
          ])
        end

        it "watches from the balance, since no usage was deducted yet" do
          expect(result).to be_success
          expect(result.alert.previous_value).to eq(1_500)
          # At the column's 0, the line at 0 would be seeded too
          expect(result.alert.all_triggered_alerts.sole.crossed_thresholds.pluck("code")).to eq(["warning"])
        end
      end
    end

    # Each create raises its wallet lock to BaselineService's mode: two creates sharing the wallet would wait on each other
    context "when two alerts are created on one wallet at once", transaction: false do
      let(:contract) { create(:contract, customer:) }
      let(:catalog_wallet) { create(:catalog_wallet, organization:, customer:, contract:, balance_cents: 1_500) }
      let(:ongoing_params) { params.merge(alert_type: "ongoing_balance", code: "low_ongoing_balance") }

      it "creates both, one after the other" do
        wallet_id = catalog_wallet.id
        arrived = Queue.new
        release = Queue.new
        allow(UsageMonitoring::CatalogWalletAlerts::BaselineService).to receive(:call!).and_wrap_original do |original, **kwargs|
          arrived << true
          release.pop
          original.call(**kwargs)
        end

        create = ->(alert_params) { Thread.new { ApplicationRecord.connection_pool.with_connection { described_class.call(catalog_wallet: CatalogWallet.find(wallet_id), params: alert_params) } } }
        first = create.call(params)
        begin
          Timeout.timeout(10) { arrived.pop }
          second = create.call(ongoing_params)
          # The second create either waits for the wallet or reaches its baseline sharing it with the first
          Timeout.timeout(10) { sleep(0.01) until lock_waits.positive? || arrived.size.positive? }
        ensure
          2.times { release << true }
        end

        expect([first, second].map { |thread| Timeout.timeout(10) { thread.value } }).to all(be_success)
        expect(CatalogWallet.find(wallet_id).alerts.pluck(:alert_type)).to contain_exactly("balance", "ongoing_balance")
      end
    end

    %i[terminated canceled].each do |status|
      context "when the contract is #{status}" do
        let(:contract) { create(:contract, status, customer:) }

        it "refuses the write and creates nothing" do
          expect(result).to be_failure
          expect(result.error).to be_a(BaseService::ForbiddenFailure)
          expect(result.error.code).to eq("contract_not_live")
          expect(catalog_wallet.alerts).to be_empty
        end
      end
    end

    context "when the wallet has ended" do
      let(:catalog_wallet) { create(:catalog_wallet, organization:, customer:, contract:, terminated_at: Time.current) }

      it "refuses the write and creates nothing" do
        expect(result).to be_failure
        expect(result.error.code).to eq("wallet_alerts_read_only")
        expect(catalog_wallet.alerts).to be_empty
      end
    end

    context "when the contract was canceled before the lock" do
      # Another request ends it: the contract the service holds stays pending until the lock reloads it
      before { Contracts::TerminateService.call!(contract: Contract.find(contract.id)) }

      it "refuses the write and creates nothing" do
        expect(result).to be_failure
        expect(result.error.code).to eq("contract_not_live")
        expect(UsageMonitoring::CatalogWalletAlert.where(catalog_wallet_id: catalog_wallet.id)).to be_empty
      end
    end

    context "when the wallet was deleted before the lock" do
      before { CatalogWallet.find(catalog_wallet.id).discard! }

      it "fails and writes nothing on it" do
        expect(result).to be_failure
        expect(result.error.error_code).to eq("contract_wallet_not_found")
        expect(UsageMonitoring::CatalogWalletAlert.where(catalog_wallet_id: catalog_wallet.id)).to be_empty
      end
    end

    context "when the wallet already has an alert of that type" do
      before { create(:catalog_wallet_alert, catalog_wallet:, organization:, alert_type: "balance", code: "other") }

      it "fails on the type index" do
        expect(result).to be_failure
        expect(result.error.messages).to eq({base: ["alert_already_exists"]})
      end
    end

    context "when the wallet already has an alert with that code" do
      before { create(:catalog_wallet_alert, catalog_wallet:, organization:, alert_type: "ongoing_balance", code: "low_balance") }

      it "fails on the code index" do
        expect(result).to be_failure
        expect(result.error.messages).to eq({code: ["value_already_exist"]})
      end
    end

    context "when another wallet has an alert with that code" do
      before { create(:catalog_wallet_alert, organization:, alert_type: "balance", code: "low_balance") }

      it "creates the alert" do
        expect(result).to be_success
      end
    end
  end
end
