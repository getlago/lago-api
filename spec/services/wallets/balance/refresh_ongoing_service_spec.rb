# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::Balance::RefreshOngoingService do
  subject(:refresh_service) { described_class.new(wallet:) }

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

  before do
    first_charge
    second_charge
    wallet
    events
  end

  describe ".call" do
    it "updates wallet ongoing balance" do
      expect { refresh_service.call }
        .to change(wallet.reload, :ongoing_usage_balance_cents).from(200).to(1100)
        .and change(wallet, :credits_ongoing_usage_balance).from(2.0).to(11.0)
        .and change(wallet, :ongoing_balance_cents).from(800).to(-100)
        .and change(wallet, :credits_ongoing_balance).from(8.0).to(-1.0)
    end

    it "returns the wallet" do
      expect(refresh_service.call.wallet).to eq(wallet)
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
        expect { refresh_service.call }
          .to change(wallet.reload, :ongoing_usage_balance_cents).from(200).to(600)
          .and change(wallet, :credits_ongoing_usage_balance).from(2.0).to(6.0)
          .and change(wallet, :ongoing_balance_cents).from(800).to(400)
          .and change(wallet, :credits_ongoing_balance).from(8.0).to(4.0)
      end

      it "returns the wallet" do
        expect(refresh_service.call.wallet).to eq(wallet)
      end
    end

    context "when there are paid in advance fees" do
      let(:third_charge) { create(:standard_charge, :pay_in_advance, plan: first_subscription.plan, billable_metric:, properties: {amount: "7"}) }
      let(:pay_in_advance_invoice) { create(:invoice, :subscription, subscriptions: [first_subscription], organization: organization, customer: customer) }
      let(:fee) do
        create(:charge_fee, charge: third_charge, subscription: first_subscription,
          organization: wallet.organization, invoice: pay_in_advance_invoice, amount_cents: 700)
      end

      before do
        fee
      end

      it "updates wallet ongoing balance" do
        # we've added one more fee to the first subscription, but the total usage is not changed
        expect { refresh_service.call }
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
        expect { refresh_service.call }
          .to change(wallet.reload, :ongoing_usage_balance_cents).from(200).to(990)
          .and change(wallet, :credits_ongoing_usage_balance).from(2.0).to(9.9)
          .and change(wallet, :ongoing_balance_cents).from(800).to(10)
          .and change(wallet, :credits_ongoing_balance).from(8.0).to(0.1)
      end

      context "when refreshing balance while finalizing progressively billed invoice" do
        subject(:refresh_service) { described_class.new(wallet:, include_generating_invoices: true) }

        before do
          invoice.generating!
        end

        it "calculates generating invoice in current usage" do
          expect { refresh_service.call }
            .to change(wallet.reload, :ongoing_usage_balance_cents).from(200).to(990)
            .and change(wallet, :credits_ongoing_usage_balance).from(2.0).to(9.9)
            .and change(wallet, :ongoing_balance_cents).from(800).to(10)
            .and change(wallet, :credits_ongoing_balance).from(8.0).to(0.1)
        end
      end
    end

    context "when recalculated ongoing balance is less than 0" do
      before do
        allow(Wallets::Balance::UpdateOngoingService).to receive(:call).and_call_original
      end

      context "when wallet is not depleted" do
        it "sends update params with depleted_ongoing_balance set to true" do
          refresh_service.call

          expect(Wallets::Balance::UpdateOngoingService).to have_received(:call)
            .with(wallet: wallet, update_params: hash_including(depleted_ongoing_balance: true))
        end
      end

      context "when wallet is depleted before the update" do
        let(:depleted_ongoing_balance) { true }

        it "doesn't send update params with depleted_ongoing_balance set to true" do
          refresh_service.call

          expect(Wallets::Balance::UpdateOngoingService).to have_received(:call)
            .with(wallet: wallet, update_params: hash_excluding(:depleted_ongoing_balance))
        end
      end
    end

    context "when failed to fetch taxes to calculate current usage" do
      let(:anrok_customer) { create(:anrok_customer, customer:) }

      before do
        anrok_customer
        allow(Integrations::Aggregator::Taxes::Invoices::CreateDraftService).to receive(:call)
          .and_return(BaseService::Result.new.service_failure!(code: "customerAddressCouldNotResolve", message: "Customer address could not resolve"))
      end

      it "fails with an error" do
        result = refresh_service.call
        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:tax_error]).to eq(["customerAddressCouldNotResolve"])
      end
    end
  end
end
