# frozen_string_literal: true

RSpec.describe Customers::RefreshWalletsService do
  describe "#call" do
    subject(:result) { described_class.call(customer:, include_generating_invoices:) }

    let(:include_generating_invoices) { false }
    let(:customer) { create(:customer) }
    let(:organization) { customer.organization }
    let(:billable_metric) { create(:billable_metric, aggregation_type: "count_agg") }
    let(:pay_in_advance_billable_metric) { create(:billable_metric, aggregation_type: "count_agg") }

    let(:subscriptions) do
      [
        create(:subscription, organization:, customer:, started_at: Time.zone.now - 2.years),
        create(:subscription, organization:, customer:, started_at: Time.zone.now - 1.year)
      ]
    end

    before do
      create(
        :wallet,
        customer:,
        balance_cents: 1000,
        ongoing_balance_cents: 1000,
        ongoing_usage_balance_cents: 0,
        credits_balance: 10.0,
        credits_ongoing_balance: 10.0,
        credits_ongoing_usage_balance: 0
      )

      create(:wallet, :terminated, customer:)

      subscriptions.map do |subscription|
        create(
          :standard_charge,
          plan: subscription.plan,
          billable_metric:,
          properties: {amount: "3"}
        )

        create(
          :standard_charge,
          plan: subscription.plan,
          billable_metric: pay_in_advance_billable_metric,
          properties: {amount: "1"},
          pay_in_advance: true,
          invoiceable: true
        )
      end

      create_pair(
        :event,
        organization:,
        subscription: subscriptions.first,
        customer:,
        code: billable_metric.code
      )

      create(
        :event,
        organization:,
        subscription: subscriptions.second,
        customer:,
        code: billable_metric.code
      )

      create(
        :event,
        organization:,
        subscription: subscriptions.second,
        customer:,
        code: pay_in_advance_billable_metric.code
      )
    end

    it "calls Wallets::Balance::RefreshOngoingUsageService for each active wallet" do
      allow(Wallets::Balance::RefreshOngoingUsageService).to receive(:call!).and_call_original

      subject

      expect(Wallets::Balance::RefreshOngoingUsageService)
        .to have_received(:call!)
        .exactly(customer.wallets.active.count).times
    end

    it "refreshes the wallet balances" do
      expect(result).to be_success
      expect(result.wallets).to match_array(customer.wallets.active)

      wallet = result.wallets.first
      expect(wallet.ongoing_usage_balance_cents).to eq 900
      expect(wallet.credits_ongoing_usage_balance).to eq 9.0
      expect(wallet.ongoing_balance_cents).to eq 100
      expect(wallet.credits_ongoing_balance).to eq 1.0
    end

    describe "current usage calculation" do
      let(:charges_to_datetime) { 1.week.from_now }
      let(:charges_from_datetime) { 1.week.ago }

      before do
        subscriptions.each do |subscription|
          create(:invoice_subscription, subscription:, charges_from_datetime:, charges_to_datetime:) do |invoice_subscription|
            create(
              :charge_fee,
              subscription:,
              precise_coupons_amount_cents: 0,
              invoice: invoice_subscription.invoice,
              amount_cents: 100,
              taxes_amount_cents: 10
            )

            invoice_subscription.invoice.update!(
              invoice_type: :progressive_billing,
              fees_amount_cents: 110,
              total_amount_cents: 110,
              status: :generating
            )
          end
        end
      end

      context "when generating invoices are included" do
        let(:include_generating_invoices) { true }

        it "returns current usage for customer including generating invoices" do
          expect(result).to be_success

          expect(result.usage_amount_cents).to match_array(
            [
              hash_including(total_usage_amount_cents: 400),
              hash_including(total_usage_amount_cents: 600)
            ]
          )

          # 400 + 600 = 1000 total usage
          # 210 + 110 = 320 billed usage (progressive billing invoices included)
          # 1000 - 320 = 680 ongoing usage
          wallet = result.wallets.first
          expect(wallet.ongoing_usage_balance_cents).to eq(680)
        end
      end

      context "when generating invoices are excluded" do
        let(:include_generating_invoices) { false }

        it "returns current usage for customer excluding generating invoices" do
          expect(result).to be_success

          expect(result.usage_amount_cents).to match_array(
            [
              hash_including(total_usage_amount_cents: 400),
              hash_including(total_usage_amount_cents: 600)
            ]
          )

          # 400 + 600 = 1000 total usage
          # 100 + 0 = 100 billed usage (progressive billing invoices excluded because they are generating)
          # 1000 - 100 = 900 ongoing usage
          wallet = result.wallets.first
          expect(wallet.ongoing_usage_balance_cents).to eq(900)
        end
      end
    end

    context "when failed to calculate current usage" do
      before do
        create(:anrok_customer, customer:)

        allow(Integrations::Aggregator::Taxes::Invoices::CreateDraftService)
          .to receive(:call)
          .and_return(
            BaseService::Result.new.service_failure!(
              code: "customerAddressCouldNotResolve",
              message: "Customer address could not resolve"
            )
          )
      end

      it "fails with an error" do
        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:tax_error]).to eq(["customerAddressCouldNotResolve"])
      end
    end
  end
end
