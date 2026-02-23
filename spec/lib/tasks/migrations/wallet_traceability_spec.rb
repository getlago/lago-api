# frozen_string_literal: true

require "rails_helper"
require "rake"

describe "migrations:wallet_traceability", type: :request, with_pdf_generation_stub: true do
  let(:task) { Rake::Task["migrations:wallet_traceability"] }
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:billing_entity) { create(:billing_entity, organization:, invoice_grace_period: 0) }
  let(:customer) { create(:customer, organization:, billing_entity:) }
  let(:plan) { create(:plan, organization:, interval: "monthly", amount_cents: 0, pay_in_advance: false) }
  let(:billable_metric) { create(:billable_metric, organization:, field_name: "total", aggregation_type: "sum_agg") }
  let(:charge) { create(:charge, plan:, billable_metric:, charge_model: "standard", properties: {"amount" => "1"}) }

  before do
    charge
    Rake.application.rake_require("tasks/migrations/wallet_traceability")
    Rake::Task.define_task(:environment)
    task.reenable
  end

  def create_non_traceable_wallet(rate_amount: "1")
    params = {
      external_customer_id: customer.external_id,
      rate_amount:,
      name: "Non-Traceable Wallet",
      currency: "EUR",
      granted_credits: "0",
      invoice_requires_successful_payment: false
    }

    wallet = create_wallet(params, as: :model)
    expect(wallet.traceable).to eq(false)
    wallet
  end

  def top_up_wallet(wallet, granted_credits: nil, paid_credits: nil)
    params = {wallet_id: wallet.id}
    params[:granted_credits] = granted_credits if granted_credits
    params[:paid_credits] = paid_credits if paid_credits

    create_wallet_transaction(params, as: :model)
  end

  def setup_subscription
    create_subscription({
      external_customer_id: customer.external_id,
      external_id: customer.external_id,
      plan_code: plan.code
    })
    customer.subscriptions.first
  end

  def ingest_usage(subscription, amount)
    create_event({
      transaction_id: SecureRandom.uuid,
      code: billable_metric.code,
      external_subscription_id: subscription.external_id,
      properties: {billable_metric.field_name => amount}
    })
    perform_usage_update
  end

  def run_migration(dry_run: nil, include_terminated: false)
    env_vars = {
      "organization_id" => organization.id,
      "batch_size" => "100",
      "output_limit" => "50"
    }
    env_vars["dry_run"] = "false" if dry_run == false
    env_vars["include_terminated"] = "true" if include_terminated

    env_vars.each { |k, v| ENV[k] = v }
    task.reenable
    task.invoke
  ensure
    env_vars&.each_key { |k| ENV.delete(k) }
  end

  describe "ENV var defaults" do
    it "defaults to dry-run when dry_run is not set" do
      wallet = create_non_traceable_wallet
      top_up_wallet(wallet, granted_credits: "100")

      ENV["organization_id"] = organization.id
      task.reenable
      task.invoke

      expect(wallet.reload.traceable).to eq(false)
    ensure
      ENV.delete("organization_id")
    end

    it "processes all organizations when organization_id is not set" do
      other_organization = create(:organization, webhook_url: nil)
      other_billing_entity = create(:billing_entity, organization: other_organization, invoice_grace_period: 0)
      other_customer = create(:customer, organization: other_organization, billing_entity: other_billing_entity)

      wallet1 = create_non_traceable_wallet
      top_up_wallet(wallet1, granted_credits: "50")

      params = {
        external_customer_id: other_customer.external_id,
        rate_amount: "1",
        name: "Other Org Wallet",
        currency: "EUR",
        granted_credits: "0",
        invoice_requires_successful_payment: false
      }
      api_call { post_with_token(other_organization, "/api/v1/wallets", {wallet: params}) }
      wallet2 = Wallet.find(json[:wallet][:lago_id])
      api_call do
        post_with_token(other_organization, "/api/v1/wallet_transactions", {
          wallet_transaction: {wallet_id: wallet2.id, granted_credits: "30"}
        })
      end

      ENV["dry_run"] = "false"
      task.reenable
      task.invoke

      expect(wallet1.reload.traceable).to eq(true)
      expect(wallet2.reload.traceable).to eq(true)
    ensure
      ENV.delete("dry_run")
    end

    it "passes thread_count env var to migration" do
      wallet = create_non_traceable_wallet
      top_up_wallet(wallet, granted_credits: "100")

      ENV["organization_id"] = organization.id
      ENV["thread_count"] = "4"
      task.reenable

      expect { task.invoke }.to output(a_string_including("Threads: 4")).to_stdout

      expect(wallet.reload.traceable).to eq(false)
    ensure
      ENV.delete("organization_id")
      ENV.delete("thread_count")
    end

    it "defaults to dry-run even when dry_run is set to any value other than 'false'" do
      wallet = create_non_traceable_wallet
      top_up_wallet(wallet, granted_credits: "100")

      ENV["dry_run"] = "true"
      ENV["organization_id"] = organization.id
      task.reenable
      task.invoke

      expect(wallet.reload.traceable).to eq(false)
    ensure
      ENV.delete("dry_run")
      ENV.delete("organization_id")
    end
  end

  describe "Dry-run mode" do
    describe "migratable wallet" do
      it "validates a wallet with consistent balance without modifying data" do
        time_0 = DateTime.new(2022, 12, 1)
        wallet = nil
        subscription = nil

        travel_to(time_0) do
          wallet = create_non_traceable_wallet
          top_up_wallet(wallet, granted_credits: "100")
          subscription = setup_subscription
        end

        travel_to(time_0 + 5.days) do
          ingest_usage(subscription, 40)
        end

        travel_to(time_0 + 1.month) do
          perform_billing
        end

        expect {
          run_migration
        }.not_to change {
                   [
                     WalletTransactionConsumption.count,
                     wallet.reload.traceable,
                     wallet.wallet_transactions.inbound.first.remaining_amount_cents
                   ]
                 }
      end
    end

    describe "CSV export on problematic wallets" do
      it "exports problematic wallets to CSV when output_file is set" do
        wallet = create_non_traceable_wallet
        top_up_wallet(wallet, granted_credits: "100")

        # Manually corrupt the balance to create drift
        Wallet.where(id: wallet.id).update_all(balance_cents: 5000, credits_balance: 50) # rubocop:disable Rails/SkipsModelValidations

        Tempfile.create(["problematic_wallets", ".csv"]) do |tmpfile|
          env_vars = {
            "organization_id" => organization.id,
            "batch_size" => "100",
            "output_limit" => "50",
            "output_file" => tmpfile.path
          }
          env_vars.each { |k, v| ENV[k] = v }
          task.reenable
          task.invoke

          csv_content = File.read(tmpfile.path)
          expect(csv_content).to include("wallet_id,customer_id,customer_name,organization_id,organization_name,created_at,issues")
          expect(csv_content).to include(wallet.id)
          expect(csv_content).to include("Balance drift")
        ensure
          env_vars&.each_key { |k| ENV.delete(k) }
        end
      end
    end

    describe "wallet with balance drift" do
      it "detects balance drift and reports it as problematic" do
        wallet = create_non_traceable_wallet
        top_up_wallet(wallet, granted_credits: "100")

        # Manually corrupt the balance to create drift
        Wallet.where(id: wallet.id).update_all(balance_cents: 5000, credits_balance: 50) # rubocop:disable Rails/SkipsModelValidations

        expect {
          run_migration
        }.to output(
          a_string_including("Problematic: 1").and(a_string_including("Balance drift >= 1 unit"))
        ).to_stdout
        expect(wallet.reload.traceable).to eq(false)
      end
    end
  end

  describe "Backfill mode" do
    describe "simple consumption" do
      # Customer tops up $100, then invoice consumes $40.
      # After backfill:
      # - One WalletTransactionConsumption: TX1 -> TX2 for $40
      # - TX1.remaining_amount_cents = 6000
      # - Wallet marked traceable

      it "creates consumption records and marks wallet traceable" do
        time_0 = DateTime.new(2022, 12, 1)
        wallet = nil
        subscription = nil

        travel_to(time_0) do
          wallet = create_non_traceable_wallet
          top_up_wallet(wallet, granted_credits: "100")
          subscription = setup_subscription
        end

        travel_to(time_0 + 5.days) do
          ingest_usage(subscription, 40)
        end

        travel_to(time_0 + 1.month) do
          perform_billing
        end

        tx1 = wallet.wallet_transactions.inbound.settled.first
        tx2 = wallet.wallet_transactions.outbound.settled.first
        expect(tx2).to be_present

        run_migration(dry_run: false)

        wallet.reload
        expect(wallet.traceable).to eq(true)

        expect(tx1.reload.remaining_amount_cents).to eq(6000)

        consumptions = WalletTransactionConsumption.where(
          inbound_wallet_transaction_id: tx1.id,
          outbound_wallet_transaction_id: tx2.id
        )
        expect(consumptions.count).to eq(1)
        expect(consumptions.first.consumed_amount_cents).to eq(4000)
      end
    end

    describe "consumption spanning multiple inbounds (FIFO)" do
      # Customer has two top-ups ($30 granted, $50 granted), then invoice consumes $60.
      # After backfill:
      # - TX1 -> TX3: $30 (TX1 fully consumed)
      # - TX2 -> TX3: $30 (TX2 partially consumed)

      it "creates consumption records following FIFO order" do
        time_0 = DateTime.new(2022, 12, 1)
        wallet = nil
        tx1 = nil
        tx2 = nil
        subscription = nil

        travel_to(time_0) do
          wallet = create_non_traceable_wallet
          top_up_wallet(wallet, granted_credits: "30")
          tx1 = wallet.wallet_transactions.inbound.first
        end

        travel_to(time_0 + 1.hour) do
          top_up_wallet(wallet, granted_credits: "50")
          tx2 = wallet.wallet_transactions.inbound.order(created_at: :desc).first
          subscription = setup_subscription
        end

        travel_to(time_0 + 5.days) do
          ingest_usage(subscription, 60)
        end

        travel_to(time_0 + 1.month) do
          perform_billing
        end

        tx3 = wallet.wallet_transactions.outbound.settled.first

        run_migration(dry_run: false)

        expect(wallet.reload.traceable).to eq(true)
        expect(tx1.reload.remaining_amount_cents).to eq(0)
        expect(tx2.reload.remaining_amount_cents).to eq(2000)

        consumptions = WalletTransactionConsumption.where(outbound_wallet_transaction_id: tx3.id)
          .order(:consumed_amount_cents)
        expect(consumptions.count).to eq(2)

        tx1_consumption = consumptions.find_by(inbound_wallet_transaction_id: tx1.id)
        tx2_consumption = consumptions.find_by(inbound_wallet_transaction_id: tx2.id)

        expect(tx1_consumption.consumed_amount_cents).to eq(3000)
        expect(tx2_consumption.consumed_amount_cents).to eq(3000)
      end
    end

    describe "multiple outbounds from same inbound" do
      # Customer tops up $100, then two billing periods consume $25 and $35.
      # After backfill:
      # - TX1 -> TX2: $25
      # - TX1 -> TX3: $35
      # - TX1.remaining_amount_cents = 4000

      it "creates separate consumption records for each outbound" do
        time_0 = DateTime.new(2022, 12, 1)
        wallet = nil
        tx1 = nil
        subscription = nil

        travel_to(time_0) do
          wallet = create_non_traceable_wallet
          top_up_wallet(wallet, granted_credits: "100")
          tx1 = wallet.wallet_transactions.inbound.first
          subscription = setup_subscription
        end

        travel_to(time_0 + 5.days) do
          ingest_usage(subscription, 25)
        end

        travel_to(time_0 + 1.month) do
          perform_billing
        end

        tx2 = wallet.wallet_transactions.outbound.settled.first

        travel_to(time_0 + 1.month + 5.days) do
          ingest_usage(subscription, 35)
        end

        travel_to(time_0 + 2.months) do
          perform_billing
        end

        tx3 = wallet.wallet_transactions.outbound.settled.order(created_at: :desc).first

        run_migration(dry_run: false)

        expect(wallet.reload.traceable).to eq(true)
        expect(tx1.reload.remaining_amount_cents).to eq(4000)

        consumptions = WalletTransactionConsumption.where(inbound_wallet_transaction_id: tx1.id)
        expect(consumptions.count).to eq(2)

        tx2_consumption = consumptions.find_by(outbound_wallet_transaction_id: tx2.id)
        tx3_consumption = consumptions.find_by(outbound_wallet_transaction_id: tx3.id)

        expect(tx2_consumption.consumed_amount_cents).to eq(2500)
        expect(tx3_consumption.consumed_amount_cents).to eq(3500)
      end
    end

    describe "priority-based consumption" do
      # Customer has: $20 granted (priority 1), $25 granted (priority 2 older),
      # $25 granted (priority 2 newer), $30 granted (priority 2 newest).
      # Invoice consumes $80. Consumption order:
      # TX1 (prio 1) -> TX2 (prio 2, oldest) -> TX3 (prio 2, newer) -> TX4 (prio 2, newest)

      it "consumes in order: granted before purchased, priority first, then FIFO" do
        time_0 = DateTime.new(2022, 12, 1)
        wallet = nil
        tx1 = nil
        tx2 = nil
        tx3 = nil
        tx4 = nil
        subscription = nil

        travel_to(time_0) do
          wallet = create_non_traceable_wallet

          transactions1 = top_up_wallet(wallet, granted_credits: "20")
          tx1 = transactions1.find(&:inbound?)
          tx1.update!(priority: 1)

          transactions2 = top_up_wallet(wallet, granted_credits: "25")
          tx2 = transactions2.find(&:inbound?)
          tx2.update!(priority: 2, created_at: 3.days.ago)

          transactions3 = top_up_wallet(wallet, granted_credits: "25")
          tx3 = transactions3.find(&:inbound?)
          tx3.update!(priority: 2, created_at: 1.day.ago)

          transactions4 = top_up_wallet(wallet, granted_credits: "30")
          tx4 = transactions4.find(&:inbound?)
          tx4.update!(priority: 2)

          subscription = setup_subscription
        end

        travel_to(time_0 + 5.days) do
          ingest_usage(subscription, 80)
        end

        travel_to(time_0 + 1.month) do
          perform_billing
        end

        tx5 = wallet.wallet_transactions.outbound.settled.first

        run_migration(dry_run: false)

        expect(wallet.reload.traceable).to eq(true)

        consumptions = WalletTransactionConsumption.where(outbound_wallet_transaction_id: tx5.id)
        expect(consumptions.count).to eq(4)

        expect(consumptions.find_by(inbound_wallet_transaction_id: tx1.id).consumed_amount_cents).to eq(2000)
        expect(consumptions.find_by(inbound_wallet_transaction_id: tx2.id).consumed_amount_cents).to eq(2500)
        expect(consumptions.find_by(inbound_wallet_transaction_id: tx3.id).consumed_amount_cents).to eq(2500)
        expect(consumptions.find_by(inbound_wallet_transaction_id: tx4.id).consumed_amount_cents).to eq(1000)

        expect(tx1.reload.remaining_amount_cents).to eq(0)
        expect(tx2.reload.remaining_amount_cents).to eq(0)
        expect(tx3.reload.remaining_amount_cents).to eq(0)
        expect(tx4.reload.remaining_amount_cents).to eq(2000)
      end
    end

    describe "granted before purchased ordering" do
      # Customer has $30 granted and $70 purchased. Invoice consumes $80.
      # Granted is consumed first, then purchased.

      it "consumes granted transactions before purchased" do
        time_0 = DateTime.new(2022, 12, 1)
        wallet = nil
        tx1 = nil
        tx2 = nil
        subscription = nil

        travel_to(time_0) do
          wallet = create_non_traceable_wallet
          top_up_wallet(wallet, granted_credits: "30")
          tx1 = wallet.wallet_transactions.inbound.where(transaction_status: :granted).first
        end

        travel_to(time_0 + 1.hour) do
          top_up_wallet(wallet, paid_credits: "70")
          tx2 = wallet.wallet_transactions.inbound.where(transaction_status: :purchased).first

          # Mark the credit invoice as paid so the purchased transaction becomes settled
          credit_invoice = customer.invoices.credit.sole
          update_invoice(credit_invoice, {payment_status: "succeeded"})
          perform_all_enqueued_jobs

          tx2.reload
          expect(tx2.status).to eq("settled")

          subscription = setup_subscription
        end

        travel_to(time_0 + 5.days) do
          ingest_usage(subscription, 80)
        end

        travel_to(time_0 + 1.month) do
          perform_billing
        end

        tx3 = wallet.wallet_transactions.outbound.settled.where(transaction_status: :invoiced).first

        run_migration(dry_run: false)

        expect(wallet.reload.traceable).to eq(true)

        consumptions = WalletTransactionConsumption.where(outbound_wallet_transaction_id: tx3.id)
        expect(consumptions.count).to eq(2)

        tx1_consumption = consumptions.find_by(inbound_wallet_transaction_id: tx1.id)
        tx2_consumption = consumptions.find_by(inbound_wallet_transaction_id: tx2.id)

        expect(tx1_consumption.consumed_amount_cents).to eq(3000)
        expect(tx2_consumption.consumed_amount_cents).to eq(5000)

        expect(tx1.reload.remaining_amount_cents).to eq(0)
        expect(tx2.reload.remaining_amount_cents).to eq(2000)
      end
    end

    describe "idempotency" do
      it "does not create duplicate records when run twice" do
        time_0 = DateTime.new(2022, 12, 1)
        wallet = nil
        subscription = nil

        travel_to(time_0) do
          wallet = create_non_traceable_wallet
          top_up_wallet(wallet, granted_credits: "100")
          subscription = setup_subscription
        end

        travel_to(time_0 + 5.days) do
          ingest_usage(subscription, 40)
        end

        travel_to(time_0 + 1.month) do
          perform_billing
        end

        run_migration(dry_run: false)

        expect(wallet.reload.traceable).to eq(true)
        consumption_count = WalletTransactionConsumption.count
        remaining = wallet.wallet_transactions.inbound.first.reload.remaining_amount_cents

        # Run again - should not change anything since wallet is now traceable
        run_migration(dry_run: false)

        expect(WalletTransactionConsumption.count).to eq(consumption_count)
        expect(wallet.wallet_transactions.inbound.first.reload.remaining_amount_cents).to eq(remaining)
      end
    end

    describe "skips already traceable wallets" do
      it "does not process wallets that are already traceable" do
        wallet = create_non_traceable_wallet
        top_up_wallet(wallet, granted_credits: "100")
        wallet.update_column(:traceable, true) # rubocop:disable Rails/SkipsModelValidations

        expect {
          run_migration(dry_run: false)
        }.not_to change(WalletTransactionConsumption, :count)
      end
    end

    describe "skips terminated wallets by default" do
      it "does not process terminated wallets unless include_terminated is set" do
        wallet = create_non_traceable_wallet
        top_up_wallet(wallet, granted_credits: "100")
        wallet.reload.update!(status: :terminated)

        expect {
          run_migration(dry_run: false)
        }.not_to change(WalletTransactionConsumption, :count)

        expect(wallet.reload.traceable).to eq(false)

        run_migration(dry_run: false, include_terminated: true)

        expect(wallet.reload.traceable).to eq(true)
      end
    end

    describe "wallet with no outbound transactions" do
      it "marks wallet as traceable and sets remaining_amount_cents" do
        wallet = create_non_traceable_wallet
        top_up_wallet(wallet, granted_credits: "100")
        tx1 = wallet.wallet_transactions.inbound.first

        run_migration(dry_run: false)

        expect(wallet.reload.traceable).to eq(true)
        expect(tx1.reload.remaining_amount_cents).to eq(10000)
      end
    end

    describe "multiple customers processed independently" do
      let(:customer2) { create(:customer, organization:, billing_entity:) }

      it "processes each customer in separate transactions" do
        time_0 = DateTime.new(2022, 12, 1)
        wallet1 = nil
        wallet2 = nil
        subscription1 = nil
        subscription2 = nil

        travel_to(time_0) do
          # Customer 1 wallet
          wallet1 = create_non_traceable_wallet
          top_up_wallet(wallet1, granted_credits: "50")
          subscription1 = setup_subscription
        end

        travel_to(time_0) do
          # Customer 2 wallet
          params = {
            external_customer_id: customer2.external_id,
            rate_amount: "1",
            name: "Customer 2 Wallet",
            currency: "EUR",
            granted_credits: "0",
            invoice_requires_successful_payment: false
          }
          wallet2 = create_wallet(params, as: :model)
          top_up_wallet(wallet2, granted_credits: "80")

          create_subscription({
            external_customer_id: customer2.external_id,
            external_id: customer2.external_id,
            plan_code: plan.code
          })
          subscription2 = customer2.subscriptions.first
        end

        travel_to(time_0 + 5.days) do
          ingest_usage(subscription1, 20)
          create_event({
            transaction_id: SecureRandom.uuid,
            code: billable_metric.code,
            external_subscription_id: subscription2.external_id,
            properties: {billable_metric.field_name => 30}
          })
          perform_usage_update
        end

        travel_to(time_0 + 1.month) do
          perform_billing
        end

        run_migration(dry_run: false)

        expect(wallet1.reload.traceable).to eq(true)
        expect(wallet2.reload.traceable).to eq(true)

        tx1 = wallet1.wallet_transactions.inbound.first
        tx2 = wallet2.wallet_transactions.inbound.first

        expect(tx1.reload.remaining_amount_cents).to eq(3000)
        expect(tx2.reload.remaining_amount_cents).to eq(5000)
      end
    end

    describe "multiple wallets for the same customer" do
      let(:billable_metric2) { create(:billable_metric, organization:, field_name: "total", aggregation_type: "sum_agg") }
      let(:charge2) { create(:charge, plan:, billable_metric: billable_metric2, charge_model: "standard", properties: {"amount" => "1"}) }

      before { charge2 }

      def create_scoped_wallet(applies_to:, granted_credits: "0")
        params = {
          external_customer_id: customer.external_id,
          rate_amount: "1",
          name: "Scoped Wallet",
          currency: "EUR",
          granted_credits:,
          invoice_requires_successful_payment: false,
          applies_to:
        }

        wallet = create_wallet(params, as: :model)
        expect(wallet.traceable).to eq(false)
        wallet
      end

      # Customer has two wallets scoped to different metrics:
      # - Wallet 1: $30 (applies to billable_metric)
      # - Wallet 2: $50 (applies to billable_metric2)
      # Invoice consumes $25 from each metric.
      # After backfill:
      # - Wallet 1: TX1 -> TX3: $25, remaining $5
      # - Wallet 2: TX2 -> TX4: $25, remaining $25
      # Both wallets marked traceable.

      it "backfills consumption records for each wallet independently" do
        time_0 = DateTime.new(2022, 12, 1)
        wallet1 = nil
        wallet2 = nil
        tx1 = nil
        tx2 = nil
        subscription = nil

        travel_to(time_0) do
          wallet1 = create_scoped_wallet(
            applies_to: {billable_metric_codes: [billable_metric.code]},
            granted_credits: "30"
          )
          tx1 = wallet1.wallet_transactions.inbound.first
        end

        travel_to(time_0 + 1.hour) do
          wallet2 = create_scoped_wallet(
            applies_to: {billable_metric_codes: [billable_metric2.code]},
            granted_credits: "50"
          )
          tx2 = wallet2.wallet_transactions.inbound.first

          subscription = setup_subscription
        end

        travel_to(time_0 + 5.days) do
          ingest_usage(subscription, 25)
          create_event({
            transaction_id: SecureRandom.uuid,
            code: billable_metric2.code,
            external_subscription_id: subscription.external_id,
            properties: {billable_metric2.field_name => 25}
          })
          perform_usage_update
        end

        travel_to(time_0 + 1.month) do
          perform_billing
        end

        run_migration(dry_run: false)

        expect(wallet1.reload.traceable).to eq(true)
        expect(wallet2.reload.traceable).to eq(true)

        tx3 = wallet1.wallet_transactions.outbound.settled.first
        tx4 = wallet2.wallet_transactions.outbound.settled.first

        consumption1 = WalletTransactionConsumption.find_by(
          inbound_wallet_transaction_id: tx1.id,
          outbound_wallet_transaction_id: tx3.id
        )
        expect(consumption1.consumed_amount_cents).to eq(2500)

        consumption2 = WalletTransactionConsumption.find_by(
          inbound_wallet_transaction_id: tx2.id,
          outbound_wallet_transaction_id: tx4.id
        )
        expect(consumption2.consumed_amount_cents).to eq(2500)

        expect(tx1.reload.remaining_amount_cents).to eq(500)
        expect(tx2.reload.remaining_amount_cents).to eq(2500)
      end

      it "only migrates non-traceable wallets, leaving already-traceable ones untouched" do
        time_0 = DateTime.new(2022, 12, 1)
        wallet1 = nil
        wallet2 = nil
        subscription = nil

        travel_to(time_0) do
          wallet1 = create_scoped_wallet(
            applies_to: {billable_metric_codes: [billable_metric.code]},
            granted_credits: "30"
          )
          # Mark wallet1 as already traceable (simulating it was already migrated)
          wallet1.update_column(:traceable, true) # rubocop:disable Rails/SkipsModelValidations
          wallet1.wallet_transactions.inbound.each do |tx|
            tx.update_column(:remaining_amount_cents, tx.amount_cents) # rubocop:disable Rails/SkipsModelValidations
          end
        end

        travel_to(time_0 + 1.hour) do
          wallet2 = create_scoped_wallet(
            applies_to: {billable_metric_codes: [billable_metric2.code]},
            granted_credits: "50"
          )

          subscription = setup_subscription
        end

        travel_to(time_0 + 5.days) do
          ingest_usage(subscription, 25)
          create_event({
            transaction_id: SecureRandom.uuid,
            code: billable_metric2.code,
            external_subscription_id: subscription.external_id,
            properties: {billable_metric2.field_name => 25}
          })
          perform_usage_update
        end

        travel_to(time_0 + 1.month) do
          perform_billing
        end

        # wallet1 is traceable, so billing already created consumption records for it
        tx3 = wallet1.wallet_transactions.outbound.settled.first
        consumption_count_before = WalletTransactionConsumption.where(outbound_wallet_transaction_id: tx3.id).count
        expect(consumption_count_before).to eq(1)

        run_migration(dry_run: false)

        # wallet1 was already traceable — migration did not create additional consumption records
        expect(WalletTransactionConsumption.where(outbound_wallet_transaction_id: tx3.id).count).to eq(consumption_count_before)

        # wallet2 was non-traceable — should now be migrated
        expect(wallet2.reload.traceable).to eq(true)
        tx4 = wallet2.wallet_transactions.outbound.settled.first
        consumption = WalletTransactionConsumption.find_by(outbound_wallet_transaction_id: tx4.id)
        expect(consumption.consumed_amount_cents).to eq(2500)
      end

      # Customer has three wallets:
      # - Wallet 1: active, non-traceable, $30 (applies to billable_metric) — should be migrated
      # - Wallet 2: terminated, non-traceable, $50 (applies to billable_metric2) — should be migrated (include_terminated)
      # - Wallet 3: active, already traceable, $20 (applies to billable_metric) — should be skipped

      it "migrates active and terminated non-traceable wallets, skips already-traceable ones" do
        time_0 = DateTime.new(2022, 12, 1)
        wallet1 = nil
        wallet2 = nil
        tx1 = nil
        tx2 = nil
        subscription = nil

        travel_to(time_0) do
          # Wallet 1: active, non-traceable
          wallet1 = create_scoped_wallet(
            applies_to: {billable_metric_codes: [billable_metric.code]},
            granted_credits: "30"
          )
          tx1 = wallet1.wallet_transactions.inbound.first
        end

        travel_to(time_0 + 1.hour) do
          # Wallet 2: will be terminated, non-traceable
          wallet2 = create_scoped_wallet(
            applies_to: {billable_metric_codes: [billable_metric2.code]},
            granted_credits: "50"
          )
          tx2 = wallet2.wallet_transactions.inbound.first

          subscription = setup_subscription
        end

        travel_to(time_0 + 5.days) do
          ingest_usage(subscription, 20)
          create_event({
            transaction_id: SecureRandom.uuid,
            code: billable_metric2.code,
            external_subscription_id: subscription.external_id,
            properties: {billable_metric2.field_name => 15}
          })
          perform_usage_update
        end

        travel_to(time_0 + 1.month) do
          perform_billing
        end

        # Terminate wallet2 after billing
        wallet2.reload.update!(status: :terminated)

        # Wallet 3: active, already traceable — created after billing so no outbound
        wallet3 = create_scoped_wallet(
          applies_to: {billable_metric_codes: [billable_metric.code]},
          granted_credits: "20"
        )
        wallet3.update_column(:traceable, true) # rubocop:disable Rails/SkipsModelValidations
        wallet3.wallet_transactions.inbound.each do |tx|
          tx.update_column(:remaining_amount_cents, tx.amount_cents) # rubocop:disable Rails/SkipsModelValidations
        end

        WalletTransactionConsumption.count

        run_migration(dry_run: false, include_terminated: true)

        # Wallet 1: active, non-traceable -> migrated
        expect(wallet1.reload.traceable).to eq(true)
        expect(tx1.reload.remaining_amount_cents).to eq(1000)
        tx3 = wallet1.wallet_transactions.outbound.settled.first
        expect(WalletTransactionConsumption.find_by(
          inbound_wallet_transaction_id: tx1.id,
          outbound_wallet_transaction_id: tx3.id
        ).consumed_amount_cents).to eq(2000)

        # Wallet 2: terminated, non-traceable -> migrated
        expect(wallet2.reload.traceable).to eq(true)
        expect(wallet2.status).to eq("terminated")
        expect(tx2.reload.remaining_amount_cents).to eq(3500)
        tx4 = wallet2.wallet_transactions.outbound.settled.first
        expect(WalletTransactionConsumption.find_by(
          inbound_wallet_transaction_id: tx2.id,
          outbound_wallet_transaction_id: tx4.id
        ).consumed_amount_cents).to eq(1500)

        # Wallet 3: already traceable -> no new consumption records
        wallet3_consumptions = WalletTransactionConsumption.where(
          inbound_wallet_transaction_id: wallet3.wallet_transactions.inbound.pluck(:id)
        )
        expect(wallet3_consumptions.count).to eq(0)
      end
    end

    describe "customer rollback when one wallet fails" do
      let(:billable_metric2) { create(:billable_metric, organization:, field_name: "total", aggregation_type: "sum_agg") }
      let(:charge2) { create(:charge, plan:, billable_metric:, charge_model: "standard", properties: {"amount" => "1"}) }

      before { charge2 }

      # Customer has two wallets:
      # - Wallet 1: migratable ($50 inbound, $20 outbound)
      # - Wallet 2: NOT migratable (inbound amount corrupted so outbound can't be consumed)
      #
      # Since all wallets for a customer are processed in a single transaction,
      # the failure on wallet2 should roll back wallet1's changes too.

      it "rolls back all wallets for the customer when one wallet fails" do
        time_0 = DateTime.new(2022, 12, 1)
        wallet1 = nil
        subscription = nil

        travel_to(time_0) do
          wallet1 = create_non_traceable_wallet
          top_up_wallet(wallet1, granted_credits: "50")

          subscription = setup_subscription
        end

        travel_to(time_0 + 5.days) do
          ingest_usage(subscription, 20)
        end

        travel_to(time_0 + 1.month) do
          perform_billing
        end

        # Create wallet2 with an inconsistent state: outbound > inbound
        wallet2 = create(:wallet, customer:, organization:, traceable: false, currency: "EUR", rate_amount: "1.00")
        inbound = create(:wallet_transaction, wallet: wallet2, organization:,
          transaction_type: :inbound, status: :settled, amount: "10.00", credit_amount: "10.00",
          transaction_status: :granted)
        create(:wallet_transaction, wallet: wallet2, organization:,
          transaction_type: :outbound, status: :settled, amount: "50.00", credit_amount: "50.00",
          transaction_status: :invoiced, created_at: inbound.created_at + 1.hour)

        run_migration(dry_run: false)

        # Neither wallet should be marked traceable
        expect(wallet1.reload.traceable).to eq(false)
        expect(wallet2.reload.traceable).to eq(false)

        # No consumption records created for either wallet
        wallet1_consumptions = WalletTransactionConsumption.where(
          inbound_wallet_transaction_id: wallet1.wallet_transactions.inbound.pluck(:id)
        )
        expect(wallet1_consumptions.count).to eq(0)

        wallet2_consumptions = WalletTransactionConsumption.where(
          inbound_wallet_transaction_id: wallet2.wallet_transactions.inbound.pluck(:id)
        )
        expect(wallet2_consumptions.count).to eq(0)
      end
    end

    describe "CSV export on backfill errors" do
      it "exports errors to CSV when output_file is set" do
        # Create wallet with inconsistent state: outbound > inbound
        wallet = create(:wallet, customer:, organization:, traceable: false, currency: "EUR", rate_amount: "1.00")
        inbound = create(:wallet_transaction, wallet:, organization:,
          transaction_type: :inbound, status: :settled, amount: "10.00", credit_amount: "10.00",
          transaction_status: :granted)
        create(:wallet_transaction, wallet:, organization:,
          transaction_type: :outbound, status: :settled, amount: "50.00", credit_amount: "50.00",
          transaction_status: :invoiced, created_at: inbound.created_at + 1.hour)

        Tempfile.create(["backfill_errors", ".csv"]) do |tmpfile|
          env_vars = {
            "organization_id" => organization.id,
            "batch_size" => "100",
            "output_limit" => "50",
            "dry_run" => "false",
            "output_file" => tmpfile.path
          }
          env_vars.each { |k, v| ENV[k] = v }
          task.reenable
          task.invoke

          csv_content = File.read(tmpfile.path)
          expect(csv_content).to include("customer_id,error")
          expect(csv_content).to include(customer.id)
        ensure
          env_vars&.each_key { |k| ENV.delete(k) }
        end
      end
    end

    describe "non-integer wallet rate" do
      it "correctly tracks consumption with non-integer rate_amount" do
        time_0 = DateTime.new(2022, 12, 1)
        wallet = nil
        subscription = nil

        travel_to(time_0) do
          wallet = create_non_traceable_wallet(rate_amount: "0.5")
          top_up_wallet(wallet, granted_credits: "100")
          subscription = setup_subscription
        end

        travel_to(time_0 + 5.days) do
          # With rate 0.5, 100 credits = 50 EUR. Usage of 30 EUR = 60 credits consumed.
          ingest_usage(subscription, 30)
        end

        travel_to(time_0 + 1.month) do
          perform_billing
        end

        tx1 = wallet.wallet_transactions.inbound.settled.first
        tx2 = wallet.wallet_transactions.outbound.settled.first

        run_migration(dry_run: false)

        expect(wallet.reload.traceable).to eq(true)

        consumption = WalletTransactionConsumption.find_by(
          inbound_wallet_transaction_id: tx1.id,
          outbound_wallet_transaction_id: tx2.id
        )
        expect(consumption).to be_present
        expect(consumption.consumed_amount_cents).to eq(3000)
        expect(tx1.reload.remaining_amount_cents).to eq(2000)
      end
    end
  end
end
