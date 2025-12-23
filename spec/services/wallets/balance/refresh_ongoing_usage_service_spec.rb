# frozen_string_literal: true

RSpec.describe Wallets::Balance::RefreshOngoingUsageService do
  let(:wallet) do
    create(
      :wallet,
      customer:,
      depleted_ongoing_balance:,
      balance_cents: 1000,
      ongoing_balance_cents: 800,
      ongoing_usage_balance_cents: 200,
      credits_balance: 10.0,
      credits_ongoing_balance: 8.0,
      credits_ongoing_usage_balance: 2.0
    )
  end

  let(:depleted_ongoing_balance) { false }
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:first_subscription) do
    create(:subscription, organization:, customer:, started_at: Time.zone.now - 2.years)
  end
  let(:second_subscription) do
    create(:subscription, organization:, customer:, started_at: Time.zone.now - 1.year)
  end
  let(:timestamp) { Time.current }
  let(:billable_metric) { create(:billable_metric, aggregation_type: "count_agg") }

  let(:first_charge) do
    create(
      :standard_charge,
      plan: first_subscription.plan,
      billable_metric:,
      properties: {amount: "3"}
    )
  end
  let(:second_charge) do
    create(
      :standard_charge,
      plan: second_subscription.plan,
      billable_metric:,
      properties: {amount: "5"}
    )
  end

  let(:events) do
    create_list(
      :event,
      2,
      organization: wallet.organization,
      subscription: first_subscription,
      customer: first_subscription.customer,
      code: billable_metric.code,
      timestamp:
    ).push(
      create(
        :event,
        organization: wallet.organization,
        subscription: second_subscription,
        customer: second_subscription.customer,
        code: billable_metric.code,
        timestamp:
      )
    )
  end

  let(:usage_amount_cents) do
    customer.active_subscriptions.map do |subscription|
      invoice = ::Invoices::CustomerUsageService.call!(customer:, subscription:).invoice

      billed_progressive_invoice_subscriptions = ::Subscriptions::ProgressiveBilledAmount
        .call(subscription:, include_generating_invoices:)
        .invoice_subscriptions

      {
        billed_progressive_invoice_subscriptions:,
        invoice:,
        subscription:
      }
    end
  end

  let(:allocation_rules) do
    Wallets::BuildAllocationRulesService.call!(customer:).allocation_rules
  end

  let(:include_generating_invoices) { false }

  before do
    first_charge
    second_charge
    wallet
    events
  end

  describe ".call" do
    subject(:result) { described_class.call(wallet:, usage_amount_cents:, allocation_rules:) }

    it "updates wallet ongoing balance" do
      expect { subject }
        .to change(wallet.reload, :ongoing_usage_balance_cents).from(200).to(1100)
        .and change(wallet, :credits_ongoing_usage_balance).from(2.0).to(11.0)
        .and change(wallet, :ongoing_balance_cents).from(800).to(-100)
        .and change(wallet, :credits_ongoing_balance).from(8.0).to(-1.0)
    end

    it "returns the wallet" do
      expect(result.wallet).to eq(wallet)
    end

    context "when there are wallet billable metric limitations" do
      let(:wallet_target) { create(:wallet_target, wallet:, billable_metric:) }
      let(:billable_metric2) { create(:billable_metric, aggregation_type: "count_agg") }
      let(:second_charge) do
        create(
          :standard_charge,
          plan: second_subscription.plan,
          billable_metric: billable_metric2,
          properties: {amount: "5"}
        )
      end
      let(:events) do
        create_list(
          :event,
          2,
          organization: wallet.organization,
          subscription: first_subscription,
          customer: first_subscription.customer,
          code: billable_metric.code,
          timestamp:
        ).push(
          create(
            :event,
            organization: wallet.organization,
            subscription: second_subscription,
            customer: second_subscription.customer,
            code: billable_metric2.code,
            timestamp:
          )
        )
      end

      before { wallet_target }

      it "updates wallet ongoing balance" do
        expect { subject }
          .to change(wallet.reload, :ongoing_usage_balance_cents).from(200).to(600)
          .and change(wallet, :credits_ongoing_usage_balance).from(2.0).to(6.0)
          .and change(wallet, :ongoing_balance_cents).from(800).to(400)
          .and change(wallet, :credits_ongoing_balance).from(8.0).to(4.0)
      end

      it "returns the wallet" do
        expect(result.wallet).to eq(wallet)
      end
    end

    context "when there are paid in advance fees" do
      let(:third_charge) { create(:standard_charge, :pay_in_advance, plan: first_subscription.plan, billable_metric:, properties: {amount: "7"}) }
      let(:pay_in_advance_invoice) { create(:invoice, :subscription, subscriptions: [first_subscription], organization: organization, customer: customer) }
      let(:fee) do
        create(:charge_fee, charge: third_charge, subscription: first_subscription,
          organization: wallet.organization, invoice: pay_in_advance_invoice, amount_cents: 700)
      end

      before { fee }

      it "updates wallet ongoing balance" do
        # we've added one more fee to the first subscription, but the total usage is not changed
        expect { subject }
          .to change(wallet.reload, :ongoing_usage_balance_cents).from(200).to(1100)
          .and change(wallet, :credits_ongoing_usage_balance).from(2.0).to(11.0)
          .and change(wallet, :ongoing_balance_cents).from(800).to(-100)
          .and change(wallet, :credits_ongoing_balance).from(8.0).to(-1.0)
      end
    end

    context "when there is a progressive billing invoice" do
      let(:invoice_type) { :progressive_billing }
      let(:timestamp) { Time.current }
      let(:charges_to_datetime) { timestamp + 1.week }
      let(:charges_from_datetime) { timestamp - 1.week }
      let(:invoice_subscription) { create(:invoice_subscription, subscription: first_subscription, charges_from_datetime:, charges_to_datetime:) }
      let(:invoice) { invoice_subscription.invoice }

      let(:fee) do
        create(:charge_fee, subscription: first_subscription, precise_coupons_amount_cents: 0,
          invoice: invoice, amount_cents: 100, taxes_amount_cents: 10)
      end

      before do
        fee
        invoice.update!(invoice_type:, fees_amount_cents: 110, total_amount_cents: 110)
      end

      it "deducts progressively_billed amount from the ongoing usage" do
        expect { subject }
          .to change(wallet.reload, :ongoing_usage_balance_cents).from(200).to(990)
          .and change(wallet, :credits_ongoing_usage_balance).from(2.0).to(9.9)
          .and change(wallet, :ongoing_balance_cents).from(800).to(10)
          .and change(wallet, :credits_ongoing_balance).from(8.0).to(0.1)
      end
    end

    context "when there are draft invoices" do
      let(:draft_invoice) { create(:invoice, :draft, customer:, organization:, total_amount_cents: 500) }
      let(:draft_fee) do
        create(
          :charge_fee,
          invoice: draft_invoice,
          charge: first_charge,
          subscription: first_subscription,
          amount_cents: 450,
          taxes_amount_cents: 50,
          precise_coupons_amount_cents: 0
        )
      end

      before { draft_fee }

      it "includes draft invoices in ongoing usage balance" do
        # Current usage: 1100, Draft invoice: 500, Total: 1600
        expect { subject }
          .to change(wallet.reload, :ongoing_usage_balance_cents).from(200).to(1600)
          .and change(wallet, :ongoing_balance_cents).from(800).to(-600)
      end
    end

    context "when there are draft invoices with billable metric limitations" do
      let(:wallet_target) { create(:wallet_target, wallet:, billable_metric:) }
      let(:billable_metric2) { create(:billable_metric, aggregation_type: "count_agg") }
      let(:second_charge) do
        create(:standard_charge, plan: second_subscription.plan, billable_metric: billable_metric2, properties: {amount: "5"})
      end
      let(:events) do
        create_list(:event, 2, organization: wallet.organization, subscription: first_subscription, customer: first_subscription.customer, code: billable_metric.code, timestamp:) +
          [create(:event, organization: wallet.organization, subscription: second_subscription, customer: second_subscription.customer, code: billable_metric2.code, timestamp:)]
      end
      let(:charge_for_other_metric) do
        create(:standard_charge, plan: first_subscription.plan, billable_metric: billable_metric2, properties: {amount: "10"})
      end
      let(:draft_invoice) { create(:invoice, :draft, customer:, organization:, total_amount_cents: 550) }
      let(:limited_fee) do
        create(
          :charge_fee,
          invoice: draft_invoice,
          charge: first_charge,
          subscription: first_subscription,
          amount_cents: 300,
          taxes_amount_cents: 30,
          precise_coupons_amount_cents: 0
        )
      end
      let(:non_limited_fee) do
        create(
          :charge_fee,
          invoice: draft_invoice,
          charge: charge_for_other_metric,
          subscription: first_subscription,
          amount_cents: 200,
          taxes_amount_cents: 20,
          precise_coupons_amount_cents: 0
        )
      end

      before do
        wallet_target
        charge_for_other_metric
        limited_fee
        non_limited_fee
      end

      it "only includes fees matching billable metric limitations from draft invoices" do
        # Current usage: 600 (limited to billable_metric)
        # Draft invoice: 330 (limited_fee only: 300 + 30)
        # Total: 930
        expect { subject }
          .to change(wallet.reload, :ongoing_usage_balance_cents).from(200).to(930)
          .and change(wallet, :ongoing_balance_cents).from(800).to(70)
      end
    end

    context "when there are draft invoices with fee type limitations" do
      let(:wallet) do
        create(
          :wallet,
          customer:,
          depleted_ongoing_balance:,
          balance_cents: 1000,
          ongoing_balance_cents: 800,
          ongoing_usage_balance_cents: 200,
          credits_balance: 10.0,
          credits_ongoing_balance: 8.0,
          credits_ongoing_usage_balance: 2.0,
          allowed_fee_types: ["subscription"]
        )
      end
      let(:draft_invoice) { create(:invoice, :draft, customer:, organization:, total_amount_cents: 550) }
      let(:subscription_fee) do
        create(
          :fee,
          invoice: draft_invoice,
          subscription: first_subscription,
          fee_type: "subscription",
          amount_cents: 100,
          precise_amount_cents: 100,
          taxes_amount_cents: 10,
          taxes_precise_amount_cents: 10,
          precise_coupons_amount_cents: 0
        )
      end
      let(:charge_fee) do
        create(
          :charge_fee,
          invoice: draft_invoice,
          charge: first_charge,
          subscription: first_subscription,
          amount_cents: 400,
          taxes_amount_cents: 40,
          precise_coupons_amount_cents: 0
        )
      end

      before do
        subscription_fee
        charge_fee
      end

      it "only includes fees matching fee type limitations from draft invoices" do
        # Current usage: 0 (charges don't count for subscription-limited wallet)
        # Draft invoice: 110 (subscription fee only: 100 + 10)
        # Total: 110
        expect { subject }
          .to change(wallet.reload, :ongoing_usage_balance_cents).from(200).to(110)
          .and change(wallet, :ongoing_balance_cents).from(800).to(890)
      end
    end

    context "when recalculated ongoing balance is less than 0" do
      before do
        allow(Wallets::Balance::UpdateOngoingService).to receive(:call).and_call_original
      end

      context "when wallet is not depleted" do
        it "sends update params with depleted_ongoing_balance set to true" do
          subject

          expect(Wallets::Balance::UpdateOngoingService).to have_received(:call)
            .with(wallet: wallet, update_params: hash_including(depleted_ongoing_balance: true))
        end
      end

      context "when wallet is depleted before the update" do
        let(:depleted_ongoing_balance) { true }

        it "doesn't send update params with depleted_ongoing_balance set to true" do
          subject

          expect(Wallets::Balance::UpdateOngoingService).to have_received(:call)
            .with(wallet: wallet, update_params: hash_excluding(:depleted_ongoing_balance))
        end
      end
    end
  end
end
