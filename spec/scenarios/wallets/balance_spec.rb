# frozen_string_literal: true

require "rails_helper"

describe "Use wallet's credits and recalculate balances", transaction: false do
  let(:organization) { create(:organization, webhook_url: nil, email_settings: [], premium_integrations: ["progressive_billing"]) }
  let(:billing_entity) { create(:billing_entity, organization:, invoice_grace_period: 10) }
  let(:plan) { create(:plan, organization: organization, interval: "monthly", amount_cents: 1_00, pay_in_advance: false) }
  let(:billable_metric) { create(:billable_metric, organization: organization, field_name: "total", aggregation_type: "sum_agg") }
  let(:charge) { create(:charge, plan: plan, billable_metric: billable_metric, charge_model: "standard", properties: {"amount" => "1"}) }
  let(:customer) { create(:customer, organization:, billing_entity:) }

  around { |test| lago_premium!(&test) }

  def ingest_event(subscription, amount)
    create_event({
      transaction_id: SecureRandom.uuid,
      code: billable_metric.code,
      external_subscription_id: subscription.external_id,
      properties: {billable_metric.field_name => amount}
    })
    perform_usage_update
  end

  def expect_to_be_a_topup_transaction(transaction, amount:, credit_amount:, metadata: [])
    expect(transaction).to be_present
    expect(transaction.source).to eq("manual")
    expect(transaction.transaction_type).to eq("inbound")
    expect(transaction.transaction_status).to eq("granted")
    expect(transaction.status).to eq("settled")
    expect(transaction.credit_amount).to eq(credit_amount)
    expect(transaction.amount).to eq(amount)
    expect(transaction.metadata).to eq(metadata)
  end

  def expect_to_be_an_invoiced_transaction(transaction, amount:, credit_amount:, metadata: [])
    expect(transaction).to be_present
    expect(transaction.source).to eq("manual")
    expect(transaction.transaction_type).to eq("outbound")
    expect(transaction.transaction_status).to eq("invoiced")
    expect(transaction.status).to eq("settled")
    expect(transaction.credit_amount).to eq(credit_amount)
    expect(transaction.amount).to eq(amount)
    expect(transaction.metadata).to eq(metadata)
  end

  def create_wallet_with_defaults(granted_credits: "10", rate_amount: "1", transaction_metadata: [])
    create_wallet({
      external_customer_id: customer.external_id,
      rate_amount: rate_amount,
      name: "Wallet1",
      currency: "EUR",
      granted_credits:,
      invoice_requires_successful_payment: false, # default
      transaction_metadata: transaction_metadata
    }, as: :model)
  end

  context "when a wallet created for a user with plain plan and usage-based charge" do
    before do
      charge
    end

    it "recalculates wallet's balance" do
      time_0 = DateTime.new(2022, 11, 30)
      wallet = nil
      travel_to time_0 do
        # Create a wallet with 10$
        wallet = create_wallet_with_defaults
        expect(wallet.credits_balance).to eq 10
        expect(wallet.balance_cents).to eq 1000
        expect(wallet.ongoing_balance_cents).to eq 1000
        expect(wallet.ongoing_usage_balance_cents).to eq 0
        expect(wallet.credits_ongoing_usage_balance).to eq 0

        expect_to_be_a_topup_transaction(wallet.wallet_transactions.first, amount: 10, credit_amount: 10)
      end

      # create a subscription
      time_1 = time_0 + 1.day
      travel_to time_1 do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code
          }
        )
      end
      subscription = customer.subscriptions.first

      # ingest events that would not use all wallet balance
      # the balance is not changed, but ongoing balance is updated
      travel_to time_1 + 5.days do
        ingest_event(subscription, 5)
        expect(subscription.invoices.count).to eq(0)
        recalculate_wallet_balances
        wallet.reload
        expect(wallet.credits_balance).to eq 10
        expect(wallet.balance_cents).to eq 1000
        expect(wallet.ongoing_balance_cents).to eq 500
        expect(wallet.ongoing_usage_balance_cents).to eq 500
        expect(wallet.credits_ongoing_balance).to eq 5
        expect(wallet.credits_ongoing_usage_balance).to eq 5

        expect(wallet.wallet_transactions.count).to eq(1)
      end

      # billing run; the invoice stays in draft:
      # balance is not changed, ongoing balance takes into account the draft invoice
      # (total amount including the subscription fee is 6$)
      time_2 = time_1 + 1.month
      travel_to time_2 do
        perform_billing
        expect(subscription.invoices.count).to eq(1)
        expect(subscription.invoices.first.status).to eq("draft")
        recalculate_wallet_balances
        wallet.reload
        expect(wallet.credits_balance).to eq 10
        expect(wallet.balance_cents).to eq 1000
        expect(wallet.ongoing_balance_cents).to eq 400
        expect(wallet.credits_ongoing_balance).to eq 4
        expect(wallet.ongoing_usage_balance_cents).to eq 600
        expect(wallet.credits_ongoing_usage_balance).to eq 6

        expect(wallet.wallet_transactions.count).to eq(1)
      end

      # ingest some events for the new billing_period
      # current usage = 6$ draft invoice + 3$ new usage = 9$
      travel_to time_2 + 5.days do
        ingest_event(subscription, 3)
        recalculate_wallet_balances
        wallet.reload
        expect(wallet.credits_balance).to eq 10
        expect(wallet.balance_cents).to eq 1000
        expect(wallet.ongoing_balance_cents).to eq 100
        expect(wallet.credits_ongoing_balance).to eq 1
        expect(wallet.ongoing_usage_balance_cents).to eq 900
        expect(wallet.credits_ongoing_usage_balance).to eq 9

        expect(wallet.wallet_transactions.count).to eq(1)
      end

      # 11th day of the billing period; the invoice is finalized
      # invoice sum = 6$ is deducted from the balance,
      # no need to recalculate balance as it's recalculated when credits are applied
      # remaining current usage is 3$
      travel_to time_2 + 10.days do
        perform_finalize_refresh
        expect(subscription.invoices.count).to eq(1)
        expect(subscription.invoices.first.status).to eq("finalized")
        wallet.reload
        expect(wallet.credits_balance).to eq 4
        expect(wallet.balance_cents).to eq 400
        expect(wallet.ongoing_balance_cents).to eq 100
        expect(wallet.credits_ongoing_balance).to eq 1
        expect(wallet.ongoing_usage_balance_cents).to eq 300
        expect(wallet.credits_ongoing_usage_balance).to eq 3

        expect(wallet.wallet_transactions.length).to eq(2)
        expect_to_be_an_invoiced_transaction(wallet.wallet_transactions.max_by(&:created_at), amount: 6, credit_amount: 6)
      end
    end
  end

  context "with pay in advance charges and taxes" do
    let(:charge) { create(:charge, :pay_in_advance, plan: plan, billable_metric: billable_metric, charge_model: "standard", properties: {"amount" => "1"}) }
    let(:tax) { create(:tax, :applied_to_billing_entity, organization: organization, rate: 10, billing_entity:) }

    before do
      charge
      tax
    end

    it "recalculates wallet's balance" do
      # Create a wallet with 100$
      wallet = create_wallet_with_defaults(granted_credits: "100")
      expect(wallet.credits_balance).to eq 100
      expect(wallet.balance_cents).to eq 10000
      expect(wallet.ongoing_balance_cents).to eq 10000
      expect(wallet.ongoing_usage_balance_cents).to eq 0
      expect(wallet.credits_ongoing_usage_balance).to eq 0

      # create a subscription
      time_0 = DateTime.new(2022, 12, 1)
      travel_to time_0 do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code
          }
        )
      end
      subscription = customer.subscriptions.first

      # ingest events that would not use all wallet balance
      # the invoice is issued, the balance is changed
      travel_to time_0 + 5.days do
        ingest_event(subscription, 50)
        expect(subscription.invoices.count).to eq(1)
        recalculate_wallet_balances
        wallet.reload
        expect(wallet.credits_balance).to eq 45
        expect(wallet.balance_cents).to eq 4500
        expect(wallet.ongoing_balance_cents).to eq 4500
        expect(wallet.credits_ongoing_balance).to eq 45
        expect(wallet.ongoing_usage_balance_cents).to eq 0
        expect(wallet.credits_ongoing_usage_balance).to eq 0

        transactions = wallet.wallet_transactions
        expect(transactions.length).to eq(2)
        # expect_to_be_an_invoiced_transaction(transactions.first, amount: 4500, credit_amount: 45)
      end

      # when the subscription invoice is generated it is not paid straight ahead with the wallet
      travel_to time_0 + 1.month do
        perform_billing
        expect(subscription.invoices.count).to eq(2)
        recalculate_wallet_balances
        wallet.reload
        expect(wallet.credits_balance).to eq 45
        expect(wallet.balance_cents).to eq 4500
        expect(wallet.ongoing_balance_cents).to eq 4390
        expect(wallet.credits_ongoing_balance).to eq 43.9
        expect(wallet.ongoing_usage_balance_cents).to eq 110
        expect(wallet.credits_ongoing_usage_balance).to eq 1.1
      end
    end
  end

  context "with 'normal' plan, with pay in advance charges plan and with threshold usage recurring set on plan" do
    let(:plan1) { create(:plan, organization: organization, interval: "monthly", amount_cents: 0, pay_in_advance: false) }
    let(:charge1) { create(:charge, plan: plan1, billable_metric: billable_metric, charge_model: "standard", properties: {"amount" => "1"}) }

    let(:plan2) { create(:plan, organization: organization, interval: "monthly", amount_cents: 0, pay_in_advance: false) }
    let(:charge2) { create(:charge, :pay_in_advance, plan: plan2, billable_metric: billable_metric, charge_model: "standard", properties: {"amount" => "2"}) }

    let(:plan3) { create(:plan, organization: organization, interval: "monthly", amount_cents: 0, pay_in_advance: false) }
    let(:charge3) { create(:charge, plan: plan3, billable_metric: billable_metric, charge_model: "standard", properties: {"amount" => "10"}) }
    let(:usage_threshold) { create(:usage_threshold, plan: plan3, amount_cents: 200_00, recurring: true) }

    let(:tax) { create(:tax, :applied_to_billing_entity, organization: organization, rate: 10, billing_entity:) }

    before { [charge1, charge2, charge3, usage_threshold, tax] }

    it "recalculates wallet's balance" do
      # create all subscriptions
      time_0 = DateTime.new(2022, 11, 30)
      wallet = nil
      travel_to time_0 do
        wallet = create_wallet_with_defaults(rate_amount: "10", granted_credits: "100", transaction_metadata: [{key: "transaction_id", value: "123"}])
        expect(wallet.credits_balance).to eq 100
        expect(wallet.balance_cents).to eq 1000_00
        expect(wallet.ongoing_balance_cents).to eq 1000_00
        expect(wallet.ongoing_usage_balance_cents).to eq 0
        expect(wallet.credits_ongoing_usage_balance).to eq 0

        transactions = wallet.wallet_transactions
        expect(transactions.length).to eq(1)

        expect_to_be_a_topup_transaction(transactions.first, amount: 1000, credit_amount: 100, metadata: [{"key" => "transaction_id", "value" => "123"}])
      end

      travel_to time_0 + 1.day do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id + "1",
            plan_code: plan1.code
          }
        )
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id + "2",
            plan_code: plan2.code
          }
        )
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id + "3",
            plan_code: plan3.code
          }
        )
      end
      subscription1 = customer.subscriptions.where(plan_id: plan1.id).first
      subscription2 = customer.subscriptions.where(plan_id: plan2.id).first
      subscription3 = customer.subscriptions.where(plan_id: plan3.id).first

      # ingest first events that would affect all subscriptions:
      # units = 10
      # sub1 total = 10 * 1 = 10 + 10% tax = 11
      # sub2 total = 10 * 2 = 20 + 10% tax = 22 - will be billed immediately
      # sub3 total = 10 * 10 = 100 + 10% tax = 110
      travel_to time_0 + 5.days do
        ingest_event(subscription1, 10)
        ingest_event(subscription2, 10)
        ingest_event(subscription3, 10)
        expect(customer.invoices.count).to eq(1)
        expect(subscription2.invoices.count).to eq(1)
        expect(subscription2.invoices.first.total_amount_cents).to eq(0)
        expect(subscription2.invoices.first.sub_total_including_taxes_amount_cents).to eq(2200)
        recalculate_wallet_balances
        wallet.reload
        # wallet balance in cents = 1000 - 22 = 978
        # ongoing balance in cents = 978 - 11 - 110 = 857
        expect(wallet.credits_balance).to eq 97.8
        expect(wallet.balance_cents).to eq 978_00
        expect(wallet.ongoing_balance_cents).to eq 857_00
        expect(wallet.credits_ongoing_balance).to eq 85.7
        expect(wallet.ongoing_usage_balance_cents).to eq 121_00
        expect(wallet.credits_ongoing_usage_balance).to eq 12.1

        transactions = wallet.wallet_transactions.sort_by(&:created_at)
        expect(transactions.length).to eq(2)

        expect_to_be_an_invoiced_transaction(transactions.last, amount: 22, credit_amount: 2.2)
      end

      # ingest second events that would affect all subscriptions
      # units = 10
      # sub1 total = 10 * 1 = 10 + 10% tax = 11
      # sub2 total = 10 * 2 = 20 + 10% tax = 22 - will be billed immediately
      # sub3 total = 10 * 10 = 100 + 10% tax = 110 - this time the progressive billing threshold is reached at 200 (110 + 110)
      travel_to time_0 + 10.days do
        ingest_event(subscription1, 10)
        ingest_event(subscription2, 10)
        ingest_event(subscription3, 10)
        perform_usage_update
        expect(customer.invoices.count).to eq(3)
        expect(subscription2.invoices.count).to eq(2)
        expect(subscription2.invoices.order(created_at: :asc).last.sub_total_including_taxes_amount_cents).to eq(22_00)
        expect(subscription3.invoices.count).to eq(1)
        expect(subscription3.invoices.first.sub_total_including_taxes_amount_cents).to eq(220_00)
        # we don't need to force refreshing wallets, because when invoices are triggered, the wallet balances are recalculated
        wallet.reload
        # wallet balance in cents = 978 - 22 - 220 = 736
        # ongoing balance in cents = 736 - 22 = 714
        expect(wallet.credits_balance).to eq 73.6
        expect(wallet.balance_cents).to eq 736_00
        expect(wallet.ongoing_balance_cents).to eq 714_00
        expect(wallet.credits_ongoing_balance).to eq 71.4
        expect(wallet.ongoing_usage_balance_cents).to eq 22_00
        expect(wallet.credits_ongoing_usage_balance).to eq 2.2

        transactions = wallet.wallet_transactions
        expect(transactions.length).to eq(4)

        third_transaction = transactions.find { |t| t.invoice_id == subscription2.invoices.last.id }
        expect_to_be_an_invoiced_transaction(third_transaction, amount: 22, credit_amount: 2.2)

        fourth_transaction = transactions.find { |t| t.invoice_id == subscription3.invoices.last.id }
        expect_to_be_an_invoiced_transaction(fourth_transaction, amount: 220, credit_amount: 22)
      end

      # ingest third event only affecting third subscription
      # units = 20
      # sub3 total = 10 * 20 = 200 + 10% tax = 220 - recurring threshold will be reached again
      travel_to time_0 + 15.days do
        ingest_event(subscription3, 20)
        perform_usage_update
        perform_all_enqueued_jobs
        expect(customer.invoices.count).to eq(4)
        expect(subscription3.invoices.count).to eq(2)
        expect(subscription3.invoices.order(created_at: :asc).last.sub_total_including_taxes_amount_cents).to eq(220_00)
        # when an invoice is issued, the wallet balances are recalculated
        wallet.reload
        # wallet balance in cents = 736 - 220 = 516
        # ongoing balance in cents = 516 - 22 = 494
        expect(wallet.credits_balance).to eq 51.6
        expect(wallet.balance_cents).to eq 516_00
        expect(wallet.ongoing_balance_cents).to eq 494_00
        expect(wallet.credits_ongoing_balance).to eq 49.4
        expect(wallet.ongoing_usage_balance_cents).to eq 22_00
        expect(wallet.credits_ongoing_usage_balance).to eq 2.2

        transactions = wallet.wallet_transactions
        expect(transactions.length).to eq(5)

        fifth_transaction = transactions.max_by(&:created_at)
        expect_to_be_an_invoiced_transaction(fifth_transaction, amount: 220, credit_amount: 22)
      end
    end
  end

  context "with multiple threshold usages set on plan" do
    let(:plan) { create(:plan, organization: organization, interval: "monthly", amount_cents: 0, pay_in_advance: false) }
    let(:charge) { create(:charge, plan: plan, billable_metric: billable_metric, charge_model: "standard", properties: {"amount" => "10"}) }
    let(:usage_threshold) { create(:usage_threshold, plan: plan, amount_cents: 200_00, recurring: false) }
    let(:usage_threshold2) { create(:usage_threshold, plan: plan, amount_cents: 500_00, recurring: false) }
    let(:usage_threshold3) { create(:usage_threshold, plan: plan, amount_cents: 200_00, recurring: true) }

    let(:tax) { create(:tax, :applied_to_billing_entity, organization: organization, rate: 10, billing_entity:) }

    before { [charge, usage_threshold, usage_threshold2, usage_threshold3, tax] }

    it "recalculates wallet's balance" do
      # Create a wallet with 1000$
      wallet = create_wallet_with_defaults(rate_amount: "10", granted_credits: "100")
      expect(wallet.credits_balance).to eq 100
      expect(wallet.balance_cents).to eq 1000_00
      expect(wallet.ongoing_balance_cents).to eq 1000_00
      expect(wallet.ongoing_usage_balance_cents).to eq 0
      expect(wallet.credits_ongoing_usage_balance).to eq 0

      # create all subscriptions
      time_0 = DateTime.new(2022, 12, 1)
      travel_to time_0 do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id + "1",
            plan_code: plan.code
          }
        )
      end
      subscription = customer.subscriptions.where(plan_id: plan.id).first

      # ingest first events - no thresholds triggered
      # units = 10
      # total = 10 * 10 = 100 + 10% tax = 110
      travel_to time_0 + 5.days do
        ingest_event(subscription, 10)
        expect(customer.invoices.count).to eq(0)
        recalculate_wallet_balances
        wallet.reload
        # wallet balance in cents = 1000
        # ongoing balance in cents = 1000 - 110 = 890
        expect(wallet.credits_balance).to eq 100
        expect(wallet.balance_cents).to eq 1000_00
        expect(wallet.ongoing_balance_cents).to eq 890_00
        expect(wallet.credits_ongoing_balance).to eq 89.0
        expect(wallet.ongoing_usage_balance_cents).to eq 110_00
        expect(wallet.credits_ongoing_usage_balance).to eq 11.0
      end

      # ingest second events that would trigger first threshold
      # units = 10
      # total = 10 * 10 = 100 + 10% tax = 110 - this time the progressive billing threshold is reached
      travel_to time_0 + 10.days do
        ingest_event(subscription, 10)
        perform_usage_update
        expect(customer.invoices.count).to eq(1)
        expect(subscription.invoices.count).to eq(1)
        expect(subscription.invoices.first.sub_total_including_taxes_amount_cents).to eq(220_00)
        # no need to force refreshing wallets, because the invoice with applied credits is generated - wallet is refreshed
        wallet.reload
        # wallet balance in cents = 1000 - 220 = 780
        # ongoing balance in cents = 780
        expect(wallet.credits_balance).to eq 78
        expect(wallet.balance_cents).to eq 780_00
        expect(wallet.ongoing_balance_cents).to eq 780_00
        expect(wallet.credits_ongoing_balance).to eq 78.0
        expect(wallet.ongoing_usage_balance_cents).to eq 0
        expect(wallet.credits_ongoing_usage_balance).to eq 0
      end

      # ingest third event only reaching the recurring threshold
      # units = 20
      # sub3 total = 10 * 20 = 200 + 10% tax = 330 - second threshold is reached
      travel_to time_0 + 15.days do
        ingest_event(subscription, 30)
        perform_usage_update
        expect(customer.invoices.count).to eq(2)
        expect(subscription.invoices.count).to eq(2)
        expect(subscription.invoices.order(created_at: :asc).last.sub_total_including_taxes_amount_cents).to eq(330_00)
        # no need to force refreshing wallets, because the invoice with applied credits is generated - wallet is refreshed
        wallet.reload
        # wallet balance in cents = 780 - 330 = 450
        # ongoing balance in cents = 450
        expect(wallet.credits_balance).to eq 45
        expect(wallet.balance_cents).to eq 450_00
        expect(wallet.ongoing_balance_cents).to eq 450_00
        expect(wallet.credits_ongoing_balance).to eq 45
        expect(wallet.ongoing_usage_balance_cents).to eq 0
        expect(wallet.credits_ongoing_usage_balance).to eq 0
      end

      # recurring threshold is reached
      travel_to time_0 + 20.days do
        ingest_event(subscription, 20)
        perform_usage_update
        expect(subscription.invoices.count).to eq(3)
        expect(subscription.invoices.order(created_at: :asc).last.sub_total_including_taxes_amount_cents).to eq(220_00)
        # no need to force refreshing wallets, because the invoice with applied credits is generated - wallet is refreshed
        wallet.reload
        # wallet balance in cents = 450 - 220 = 230
        # ongoing balance in cents = 230
        expect(wallet.credits_balance).to eq 23
        expect(wallet.balance_cents).to eq 230_00
        expect(wallet.ongoing_balance_cents).to eq 230_00
        expect(wallet.credits_ongoing_balance).to eq 23
        expect(wallet.ongoing_usage_balance_cents).to eq 0
        expect(wallet.credits_ongoing_usage_balance).to eq 0
      end
    end
  end
end
