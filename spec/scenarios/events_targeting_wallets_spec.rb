# frozen_string_literal: true

require "rails_helper"

describe "Events Targeting Wallets Scenarios", transaction: false do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:) }

  describe "pay in arrears charges with wallet targeting" do
    around { |test| lago_premium!(&test) }

    let(:plan) { create(:plan, organization:, amount_cents: 0) }
    let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "sum_agg", field_name: "value") }

    let(:charge) do
      create(
        :standard_charge,
        plan:,
        billable_metric:,
        accepts_target_wallet: true,
        properties: {amount: "10"}
      )
    end

    let(:wallet1) { create(:wallet, customer:, code: "wallet_1", name: "Wallet 1") }
    let(:wallet2) { create(:wallet, customer:, code: "wallet_2", name: "Wallet 2") }

    before do
      organization.update!(premium_integrations: ["event_wallet_target"])
      charge
    end

    it "groups fees by target_wallet_code in invoice" do
      jan15 = DateTime.new(2023, 1, 15)

      travel_to(jan15) do
        wallet1
        wallet2

        create_subscription({
          external_customer_id: customer.external_id,
          external_id: "sub_wallet_test",
          plan_code: plan.code
        })
      end

      subscription = customer.subscriptions.find_by(external_id: "sub_wallet_test")

      # Send events with different target_wallet_code values
      travel_to(jan15 + 1.day) do
        create_event({
          code: billable_metric.code,
          transaction_id: SecureRandom.uuid,
          external_subscription_id: subscription.external_id,
          properties: {value: "10", target_wallet_code: "wallet_1"}
        })

        create_event({
          code: billable_metric.code,
          transaction_id: SecureRandom.uuid,
          external_subscription_id: subscription.external_id,
          properties: {value: "5", target_wallet_code: "wallet_1"}
        })

        create_event({
          code: billable_metric.code,
          transaction_id: SecureRandom.uuid,
          external_subscription_id: subscription.external_id,
          properties: {value: "20", target_wallet_code: "wallet_2"}
        })
      end

      # Bill the subscription at end of month
      travel_to(DateTime.new(2023, 2, 1)) do
        perform_billing
      end

      # Verify invoice has correct grouped fees
      invoice = subscription.invoices.first
      expect(invoice).to be_present

      charge_fees = invoice.fees.charge
      expect(charge_fees.count).to eq(2)

      wallet1_fee = charge_fees.find { |f| f.grouped_by["target_wallet_code"] == "wallet_1" }
      wallet2_fee = charge_fees.find { |f| f.grouped_by["target_wallet_code"] == "wallet_2" }

      expect(wallet1_fee.units).to eq(15)
      expect(wallet1_fee.amount_cents).to eq(15_000)

      expect(wallet2_fee.units).to eq(20)
      expect(wallet2_fee.amount_cents).to eq(20_000)
    end

    context "with pricing_group_keys and wallet targeting combined" do
      let(:charge) do
        create(
          :standard_charge,
          plan:,
          billable_metric:,
          accepts_target_wallet: true,
          properties: {
            amount: "5",
            pricing_group_keys: ["region"]
          }
        )
      end

      it "groups fees by both pricing_group_keys and target_wallet_code" do
        jan15 = DateTime.new(2023, 1, 15)

        travel_to(jan15) do
          wallet1
          wallet2

          create_subscription({
            external_customer_id: customer.external_id,
            external_id: "sub_combined",
            plan_code: plan.code
          })
        end

        subscription = customer.subscriptions.find_by(external_id: "sub_combined")

        # Send events with different combinations of region and target_wallet_code
        travel_to(jan15 + 1.day) do
          # wallet_1, region: eu
          create_event({
            code: billable_metric.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: subscription.external_id,
            properties: {value: "10", region: "eu", target_wallet_code: "wallet_1"}
          })

          # wallet_1, region: us
          create_event({
            code: billable_metric.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: subscription.external_id,
            properties: {value: "15", region: "us", target_wallet_code: "wallet_1"}
          })

          # wallet_2, region: eu
          create_event({
            code: billable_metric.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: subscription.external_id,
            properties: {value: "20", region: "eu", target_wallet_code: "wallet_2"}
          })
        end

        # Bill at end of month
        travel_to(DateTime.new(2023, 2, 1)) do
          perform_billing
        end

        invoice = subscription.invoices.first
        charge_fees = invoice.fees.charge

        # Should have 3 fees: (wallet_1, eu), (wallet_1, us), (wallet_2, eu)
        expect(charge_fees.count).to eq(3)

        wallet1_eu_fee = charge_fees.find { |f| f.grouped_by["target_wallet_code"] == "wallet_1" && f.grouped_by["region"] == "eu" }
        wallet1_us_fee = charge_fees.find { |f| f.grouped_by["target_wallet_code"] == "wallet_1" && f.grouped_by["region"] == "us" }
        wallet2_eu_fee = charge_fees.find { |f| f.grouped_by["target_wallet_code"] == "wallet_2" && f.grouped_by["region"] == "eu" }

        expect(wallet1_eu_fee.units).to eq(10)
        expect(wallet1_eu_fee.amount_cents).to eq(5_000)

        expect(wallet1_us_fee.units).to eq(15)
        expect(wallet1_us_fee.amount_cents).to eq(7_500)

        expect(wallet2_eu_fee.units).to eq(20)
        expect(wallet2_eu_fee.amount_cents).to eq(10_000)
      end
    end
  end

  describe "pay in advance charges with wallet targeting" do
    around { |test| lago_premium!(&test) }

    let(:plan) { create(:plan, organization:, amount_cents: 0) }
    let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "sum_agg", field_name: "value") }

    let(:charge) do
      create(
        :standard_charge,
        :pay_in_advance,
        invoiceable: false,
        plan:,
        billable_metric:,
        accepts_target_wallet: true,
        properties: {amount: "10"}
      )
    end

    let(:wallet1) { create(:wallet, customer:, code: "wallet_1", name: "Wallet 1") }
    let(:wallet2) { create(:wallet, customer:, code: "wallet_2", name: "Wallet 2") }

    before do
      organization.update!(premium_integrations: ["event_wallet_target"])
      charge
    end

    it "creates pay_in_advance fees grouped by target_wallet_code" do
      jan15 = DateTime.new(2023, 1, 15)

      travel_to(jan15) do
        wallet1
        wallet2

        create_subscription({
          external_customer_id: customer.external_id,
          external_id: "sub_advance",
          plan_code: plan.code
        })
      end

      subscription = customer.subscriptions.find_by(external_id: "sub_advance")

      # Send events - each should create a pay_in_advance fee
      travel_to(jan15 + 1.day) do
        expect do
          create_event({
            code: billable_metric.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: subscription.external_id,
            properties: {value: "10", target_wallet_code: "wallet_1"}
          })
        end.to change { subscription.reload.fees.count }.from(0).to(1)

        fee1 = subscription.fees.order(created_at: :desc).first
        expect(fee1.pay_in_advance).to eq(true)
        expect(fee1.units).to eq(10)
        expect(fee1.amount_cents).to eq(10_000)
        expect(fee1.grouped_by["target_wallet_code"]).to eq("wallet_1")
      end

      travel_to(jan15 + 2.days) do
        expect do
          create_event({
            code: billable_metric.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: subscription.external_id,
            properties: {value: "5", target_wallet_code: "wallet_2"}
          })
        end.to change { subscription.reload.fees.count }.from(1).to(2)

        fee2 = subscription.fees.order(created_at: :desc).first
        expect(fee2.pay_in_advance).to eq(true)
        expect(fee2.units).to eq(5)
        expect(fee2.amount_cents).to eq(5_000)
        expect(fee2.grouped_by["target_wallet_code"]).to eq("wallet_2")
      end
    end
  end

  describe "events without target_wallet_code on accepting charge" do
    around { |test| lago_premium!(&test) }

    let(:plan) { create(:plan, organization:, amount_cents: 0) }
    let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "sum_agg", field_name: "value") }

    let(:charge) do
      create(
        :standard_charge,
        plan:,
        billable_metric:,
        accepts_target_wallet: true,
        properties: {amount: "10"}
      )
    end

    let(:wallet1) { create(:wallet, customer:, code: "wallet_1", name: "Wallet 1") }

    before do
      organization.update!(premium_integrations: ["event_wallet_target"])
      charge
    end

    it "handles mix of events with and without target_wallet_code" do
      jan15 = DateTime.new(2023, 1, 15)

      travel_to(jan15) do
        wallet1

        create_subscription({
          external_customer_id: customer.external_id,
          external_id: "sub_mixed",
          plan_code: plan.code
        })
      end

      subscription = customer.subscriptions.find_by(external_id: "sub_mixed")

      travel_to(jan15 + 1.day) do
        # Event with wallet
        create_event({
          code: billable_metric.code,
          transaction_id: SecureRandom.uuid,
          external_subscription_id: subscription.external_id,
          properties: {value: "10", target_wallet_code: "wallet_1"}
        })

        # Event without wallet
        create_event({
          code: billable_metric.code,
          transaction_id: SecureRandom.uuid,
          external_subscription_id: subscription.external_id,
          properties: {value: "5"}
        })
      end

      # Bill at end of month
      travel_to(DateTime.new(2023, 2, 1)) do
        perform_billing
      end

      invoice = subscription.invoices.first
      charge_fees = invoice.fees.charge

      expect(charge_fees.count).to eq(2)

      wallet_fee = charge_fees.find { |f| f.grouped_by["target_wallet_code"] == "wallet_1" }
      no_wallet_fee = charge_fees.find { |f| f.grouped_by.empty? || f.grouped_by["target_wallet_code"].nil? }

      expect(wallet_fee.units).to eq(10)
      expect(wallet_fee.amount_cents).to eq(10_000)

      expect(no_wallet_fee.units).to eq(5)
      expect(no_wallet_fee.amount_cents).to eq(5_000)
    end
  end
end
