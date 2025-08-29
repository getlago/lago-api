# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppliedCoupon, type: :model do
  subject(:applied_coupon) { create(:applied_coupon) }

  it_behaves_like "paper_trail traceable"

  describe "#remaining_amount" do
    let(:applied_coupon) { create(:applied_coupon, amount_cents: 50) }
    let(:invoice) { create(:invoice) }

    before do
      create(:credit, applied_coupon: applied_coupon, amount_cents: 10, invoice: invoice)
    end

    context "when invoice is not voided" do
      it "returns the amount minus credit" do
        expect(applied_coupon.remaining_amount).to eq(40)
      end
    end

    context "when invoice is voided" do
      let(:invoice) { create(:invoice, status: :voided) }

      it "ignores the credit amount" do
        expect(applied_coupon.remaining_amount).to eq(50)
      end
    end
  end

  describe "#remaining_amount_for_this_subscription_billing_period" do
    let(:applied_coupon) { create(:applied_coupon, amount_cents: 100) }
    let(:organization) { applied_coupon.organization }
    let(:customer) { applied_coupon.customer }
    let(:subscription) { create(:subscription, customer:, organization:) }
    let(:current_time) { Time.current }
    let(:invoice) { create(:invoice, :subscription, customer:, organization:, subscriptions: [subscription]) }
    let(:invoice_fee) do
      create(:fee, invoice:, subscription:, amount_cents: 20, organization:,
        properties: {charges_from_datetime: current_time.beginning_of_month,
                     charges_to_datetime: current_time.end_of_month})
    end

    before do
      invoice.invoice_subscriptions.update(timestamp: current_time, charges_from_datetime: current_time.beginning_of_month, charges_to_datetime: current_time.end_of_month)
      invoice_fee
    end

    context "when no credits exist for the billing period" do
      it "returns the full amount" do
        expect(applied_coupon.remaining_amount_for_this_subscription_billing_period(invoice: invoice)).to eq(100)
      end
    end

    context "when credits exist for another invoice in the same billing period" do
      let(:other_invoice) { create(:invoice, :subscription, customer:, organization:, subscriptions: [subscription]) }
      let(:credit) do
        create(:credit,
          applied_coupon: applied_coupon,
          invoice: other_invoice,
          amount_cents: 30,
          organization:)
      end
      let(:other_invoice_fee) do
        create(:fee, invoice: other_invoice, subscription:, amount_cents: 20,
          properties: {charges_from_datetime: current_time.beginning_of_month,
                       charges_to_datetime: current_time.end_of_month})
      end

      before do
        other_invoice.invoice_subscriptions.update(timestamp: current_time, charges_from_datetime: current_time.beginning_of_month,
          charges_to_datetime: current_time.end_of_month)
        other_invoice_fee
        credit
      end

      it "returns the amount minus the credit" do
        expect(applied_coupon.remaining_amount_for_this_subscription_billing_period(invoice: invoice)).to eq(70)
      end
    end

    context "when credits exist in non-overlapping billing periods" do
      let(:other_invoice) { create(:invoice, :subscription, customer:, organization:, subscriptions: [subscription]) }
      let(:other_invoice_fee) do
        create(:fee, invoice: other_invoice, subscription:, amount_cents: 20, organization:,
          properties: {charges_from_datetime: current_time.beginning_of_month - 1.month,
                       charges_to_datetime: current_time.end_of_month - 1.month})
      end

      before do
        other_invoice.invoice_subscriptions.update(timestamp: current_time, charges_from_datetime: current_time.beginning_of_month - 1.month, charges_to_datetime: current_time.end_of_month - 1.month)
        other_invoice_fee
        create(:credit,
          applied_coupon: applied_coupon,
          invoice: other_invoice,
          amount_cents: 40,
          organization:)
      end

      it "excludes credits from invoices with non-overlapping billing periods" do
        expect(applied_coupon.remaining_amount_for_this_subscription_billing_period(invoice: invoice)).to eq(100)
      end
    end

    context "when credits exceed the original amount" do
      let(:credit) do
        create(:credit,
          applied_coupon:,
          invoice:,
          amount_cents: 150,
          organization:)
      end

      before do
        credit
      end

      it "returns 0 (never negative)" do
        expect(applied_coupon.remaining_amount_for_this_subscription_billing_period(invoice: invoice)).to eq(0)
      end
    end

    context "when invoice has voided credits" do
      let(:voided_invoice) { create(:invoice, :subscription, :voided, customer:, organization:, subscriptions: [subscription]) }
      let(:voided_invoice_fee) do
        create(:fee, invoice: voided_invoice, subscription:, amount_cents: 20,
          properties: {charges_from_datetime: current_time.beginning_of_month,
                       charges_to_datetime: current_time.end_of_month})
      end

      before do
        voided_invoice.invoice_subscriptions.update(timestamp: current_time, charges_from_datetime: current_time.beginning_of_month, charges_to_datetime: current_time.end_of_month)
        voided_invoice_fee
        create(:credit,
          applied_coupon: applied_coupon,
          invoice: voided_invoice,
          amount_cents: 50,
          organization: organization)
      end

      it "ignores voided invoice credits" do
        expect(applied_coupon.remaining_amount_for_this_subscription_billing_period(invoice: invoice)).to eq(100)
      end
    end

    context "when called multiple times with the same invoice" do
      it "caches the result" do
        first_call = applied_coupon.remaining_amount_for_this_subscription_billing_period(invoice: invoice)
        second_call = applied_coupon.remaining_amount_for_this_subscription_billing_period(invoice: invoice)

        expect(first_call).to eq(second_call)
        expect(first_call).to eq(100)
      end
    end

    context "when invoice has multiple subscriptions with same billing period" do
      let(:subscription_2) { create(:subscription, customer: customer, organization: organization) }
      let(:invoice_subscription_2) do
        create(:invoice_subscription,
          invoice: invoice,
          subscription: subscription_2,
          organization: organization,
          timestamp: current_time,
          charges_from_datetime: current_time.beginning_of_month,
          charges_to_datetime: current_time.end_of_month)
      end
      let(:invoice_fee_2) do
        create(:fee, invoice: invoice, subscription: subscription_2, amount_cents: 20, organization:,
          properties: {charges_from_datetime: current_time.beginning_of_month,
                       charges_to_datetime: current_time.end_of_month})
      end

      # this credit is associated to subscription 1 and subscription 2
      before do
        invoice_subscription_2
        create(:credit,
          applied_coupon: applied_coupon,
          invoice: invoice,
          amount_cents: 20,
          organization: organization)
        invoice_fee_2
      end

      it "calculates based on the minimum used amount across all subscriptions" do
        expect(applied_coupon.remaining_amount_for_this_subscription_billing_period(invoice: invoice)).to eq(80)
      end

      context "when each subscription has different remaining amount of the coupon" do
        let(:invoice_2) { create(:invoice, :subscription, customer:, organization:, subscriptions: [subscription_2]) }
        let(:invoice_2_fee) do
          create(:fee, invoice: invoice_2, subscription: subscription_2, amount_cents: 20, organization:,
            properties: {charges_from_datetime: current_time.beginning_of_month,
                         charges_to_datetime: current_time.end_of_month})
        end

        # this credit is associated only to subscription 2
        let(:credit_2) { create(:credit, applied_coupon:, invoice: invoice_2, amount_cents: 30, organization:) }

        before do
          invoice_2.invoice_subscriptions.update(timestamp: current_time, charges_from_datetime: current_time.beginning_of_month, charges_to_datetime: current_time.end_of_month)
          credit_2
          invoice_2_fee
        end

        # Note: subscription_2 has 50 credits, becasue it's associated to invoice and invoice_2,
        # but subscription has 20 credits, so the remaining amount is 80
        it "calculates based on the minimum used amount across all subscriptions" do
          invoice.reload
          expect(applied_coupon.remaining_amount_for_this_subscription_billing_period(invoice: invoice)).to eq(80)
        end
      end

      context "when one of subscription has no usage" do
        let(:subscription_3) { create(:subscription, customer:, organization:) }
        let(:invoice_3) { create(:invoice, :subscription, customer:, organization:, subscriptions: [subscription_3, subscription_2]) }
        let(:invoice_3_fee) do
          create(:fee, invoice: invoice_3, subscription: subscription_3, amount_cents: 20, organization:,
            properties: {charges_from_datetime: current_time.beginning_of_month,
                         charges_to_datetime: current_time.end_of_month})
        end

        before do
          invoice_3.invoice_subscriptions.update(timestamp: current_time, charges_from_datetime: current_time.beginning_of_month, charges_to_datetime: current_time.end_of_month)
          invoice_3_fee
        end

        it "calculates based on the minimum used amount across all subscriptions" do
          expect(applied_coupon.remaining_amount_for_this_subscription_billing_period(invoice: invoice_3)).to eq(100)
        end
      end
    end
  end

  describe "#credits_sum_for_invoice_subscription" do
    let(:applied_coupon) { create(:applied_coupon) }
    let(:organization) { applied_coupon.organization }
    let(:customer) { applied_coupon.customer }
    let(:subscription) { create(:subscription, customer:, organization:) }
    let(:billing_entity) { organization.default_billing_entity }
    let(:current_time) { Time.current }
    let(:charges_from) { current_time.beginning_of_month }
    let(:charges_to) { current_time.end_of_month }
    let(:invoice) { create(:invoice, customer:, organization:, billing_entity:) }
    let(:invoice_subscription) do
      create(:invoice_subscription,
        invoice:,
        subscription:,
        organization:,
        charges_from_datetime: charges_from,
        charges_to_datetime: charges_to)
    end

    before do
      invoice_subscription
    end

    context "when fees exist with matching billing period boundaries and credits exist" do
      let(:fee) do
        create(:fee,
          invoice:,
          subscription:,
          organization:,
          billing_entity:,
          properties: {
            "charges_from_datetime" => charges_from.iso8601,
            "charges_to_datetime" => charges_to.iso8601
          })
      end
      let(:credit) do
        create(:credit,
          applied_coupon: applied_coupon,
          invoice:,
          amount_cents: 50,
          organization:)
      end

      before do
        fee
        credit
      end

      it "returns the sum of credits for matching invoice IDs" do
        result = applied_coupon.credits_sum_for_invoice_subscription(invoice_subscription, invoice)
        expect(result).to eq(50)
      end
    end

    context "when fees exist but outside billing period boundaries" do
      let(:other_invoice) { create(:invoice, customer:, organization:, billing_entity:) }
      let(:fee) do
        create(:fee,
          invoice: other_invoice,
          subscription:,
          organization:,
          billing_entity:,
          properties: {
            "charges_from_datetime" => (charges_from - 1.month).iso8601,
            "charges_to_datetime" => (charges_to - 1.month).iso8601
          })
      end
      let(:credit) do
        create(:credit,
          applied_coupon:,
          invoice: other_invoice,
          amount_cents: 50,
          organization:)
      end

      before do
        fee
        credit
      end

      it "returns 0 as no fees match the billing period" do
        result = applied_coupon.credits_sum_for_invoice_subscription(invoice_subscription, invoice)
        expect(result).to eq(0)
      end
    end

    context "when no fees exist for the subscription" do
      it "returns 0" do
        result = applied_coupon.credits_sum_for_invoice_subscription(invoice_subscription, invoice)
        expect(result).to eq(0)
      end
    end

    context "when credits exist but for voided invoices" do
      let(:voided_invoice) { create(:invoice, customer:, organization:, billing_entity:, status: :voided) }
      let(:fee) do
        create(:fee,
          invoice: voided_invoice,
          subscription:,
          organization:,
          billing_entity:,
          properties: {
            "charges_from_datetime" => charges_from.iso8601,
            "charges_to_datetime" => charges_to.iso8601
          })
      end
      let(:credit) do
        create(:credit,
          applied_coupon:,
          invoice: voided_invoice,
          amount_cents: 50,
          organization:)
      end

      before do
        fee
        credit
      end

      it "excludes credits from voided invoices" do
        result = applied_coupon.credits_sum_for_invoice_subscription(invoice_subscription, invoice)
        expect(result).to eq(0)
      end
    end

    context "when no credits exist" do
      let(:fee) do
        create(:fee,
          invoice:,
          subscription:,
          organization:,
          billing_entity:,
          properties: {
            "charges_from_datetime" => charges_from.iso8601,
            "charges_to_datetime" => charges_to.iso8601
          })
      end

      before do
        fee
      end

      it "returns 0" do
        result = applied_coupon.credits_sum_for_invoice_subscription(invoice_subscription, invoice)
        expect(result).to eq(0)
      end
    end

    context "when multiple fees exist for the same subscription in different invoices" do
      let(:fee_1) do
        create(:fee,
          invoice:,
          subscription:,
          organization:,
          billing_entity:,
          properties: {
            "charges_from_datetime" => charges_from.iso8601,
            "charges_to_datetime" => charges_to.iso8601
          })
      end
      let(:invoice_2) { create(:invoice, customer:, organization:, billing_entity:) }
      let(:fee_2) do
        create(:fee,
          invoice: invoice_2,
          subscription:,
          organization:,
          billing_entity:,
          properties: {
            "charges_from_datetime" => charges_from.iso8601,
            "charges_to_datetime" => charges_to.iso8601
          })
      end
      let(:credit_1) do
        create(:credit,
          applied_coupon:,
          invoice:,
          amount_cents: 25,
          organization:)
      end
      let(:credit_2) do
        create(:credit,
          applied_coupon:,
          invoice: invoice_2,
          amount_cents: 35,
          organization:)
      end

      before do
        fee_1
        fee_2
        credit_1
        credit_2
      end

      it "sums credits from all matching invoices" do
        result = applied_coupon.credits_sum_for_invoice_subscription(invoice_subscription, invoice)
        expect(result).to eq(60)
      end
    end
  end

  describe "#credits_applied_in_billing_period_present?" do
    let(:applied_coupon) { create(:applied_coupon) }
    let(:organization) { applied_coupon.organization }
    let(:customer) { applied_coupon.customer }
    let(:subscription) { create(:subscription, customer:, organization:) }
    let(:billing_entity) { organization.default_billing_entity }
    let(:current_time) { Time.current }
    let(:charges_from) { current_time.beginning_of_month }
    let(:charges_to) { current_time.end_of_month }
    let(:invoice) { create(:invoice, customer:, organization:, billing_entity:) }
    let(:invoice_subscription) do
      create(:invoice_subscription,
        invoice:,
        subscription:,
        organization: organization,
        charges_from_datetime: charges_from,
        charges_to_datetime: charges_to)
    end

    before do
      invoice_subscription
    end

    context "when credits are applied in the billing period" do
      let(:fee) do
        create(:fee,
          invoice:,
          subscription:,
          organization:,
          billing_entity:,
          properties: {
            "charges_from_datetime" => charges_from.iso8601,
            "charges_to_datetime" => charges_to.iso8601
          })
      end
      let(:credit) do
        create(:credit,
          applied_coupon:,
          invoice:,
          amount_cents: 50,
          organization:)
      end

      before do
        fee
        credit
      end

      it "returns true" do
        result = applied_coupon.credits_applied_in_billing_period_present?(invoice)
        expect(result).to be true
      end
    end

    context "when no credits are applied in the billing period" do
      let(:fee) do
        create(:fee,
          invoice:,
          subscription:,
          organization:,
          billing_entity:,
          properties: {
            "charges_from_datetime" => charges_from.iso8601,
            "charges_to_datetime" => charges_to.iso8601
          })
      end

      before do
        fee
      end

      it "returns false" do
        result = applied_coupon.credits_applied_in_billing_period_present?(invoice)
        expect(result).to be false
      end
    end

    context "when credits exist but for voided invoices" do
      let(:voided_invoice) { create(:invoice, customer:, organization:, billing_entity:, status: :voided) }
      let(:voided_invoice_subscription) do
        create(:invoice_subscription,
          invoice: voided_invoice,
          subscription:,
          organization:,
          charges_from_datetime: charges_from,
          charges_to_datetime: charges_to)
      end
      let(:fee) do
        create(:fee,
          invoice: voided_invoice,
          subscription:,
          organization:,
          billing_entity:,
          properties: {
            "charges_from_datetime" => charges_from.iso8601,
            "charges_to_datetime" => charges_to.iso8601
          })
      end
      let(:credit) do
        create(:credit,
          applied_coupon:,
          invoice: voided_invoice,
          amount_cents: 50,
          organization:)
      end

      before do
        voided_invoice_subscription
        fee
        credit
      end

      it "returns false as voided invoice credits are excluded" do
        result = applied_coupon.credits_applied_in_billing_period_present?(invoice)
        expect(result).to be false
      end
    end

    context "when invoice has multiple subscriptions with mixed credit scenarios" do
      let(:subscription_2) { create(:subscription, customer:, organization:) }
      let(:invoice_subscription_2) do
        create(:invoice_subscription,
          invoice:,
          subscription: subscription_2,
          organization:,
          charges_from_datetime: charges_from,
          charges_to_datetime: charges_to)
      end
      let(:fee_1) do
        create(:fee,
          invoice:,
          subscription:,
          organization:,
          billing_entity:,
          properties: {
            "charges_from_datetime" => charges_from.iso8601,
            "charges_to_datetime" => charges_to.iso8601
          })
      end
      let(:fee_2) do
        create(:fee,
          invoice:,
          subscription: subscription_2,
          organization:,
          billing_entity:,
          properties: {
            "charges_from_datetime" => charges_from.iso8601,
            "charges_to_datetime" => charges_to.iso8601
          })
      end
      let(:credit) do
        create(:credit,
          applied_coupon:,
          invoice:,
          amount_cents: 30,
          organization:)
      end

      before do
        invoice_subscription_2
        fee_1
        fee_2
        credit
      end

      it "returns true when at least one subscription has credits" do
        result = applied_coupon.credits_applied_in_billing_period_present?(invoice)
        expect(result).to be true
      end
    end

    context "when credits exist but for invoice with fees outside billing period boundaries" do
      let(:other_invoice) { create(:invoice, customer:, organization:, billing_entity:) }
      let(:fee) do
        create(:fee,
          invoice: other_invoice,
          subscription:,
          organization:,
          billing_entity:,
          properties: {
            "charges_from_datetime" => (charges_from - 1.month).iso8601,
            "charges_to_datetime" => (charges_to - 1.month).iso8601
          })
      end
      let(:credit) do
        create(:credit,
          applied_coupon:,
          invoice: other_invoice,
          amount_cents: 50,
          organization:)
      end

      before do
        fee
        credit
      end

      it "returns false as credits are outside the billing period" do
        result = applied_coupon.credits_applied_in_billing_period_present?(invoice)
        expect(result).to be false
      end
    end
  end
end
