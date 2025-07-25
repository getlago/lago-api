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
    let(:subscription) { create(:subscription, customer: customer, organization: organization) }
    let(:current_time) { Time.current }
    let(:invoice) { create(:invoice, :subscription, customer: customer, organization: organization, subscriptions: [subscription]) }

    before do
      invoice.invoice_subscriptions.update(timestamp: current_time, charges_from_datetime: current_time.beginning_of_month, charges_to_datetime: current_time.end_of_month)
    end

    context "when no credits exist for the billing period" do
      it "returns the full amount" do
        expect(applied_coupon.remaining_amount_for_this_subscription_billing_period(invoice: invoice)).to eq(100)
      end
    end

    context "when credits exist for another invoice in the same billing period" do
      let(:other_invoice) { create(:invoice, :subscription, customer: customer, organization: organization, subscriptions: [subscription]) }
      let(:credit) do
        create(:credit,
          applied_coupon: applied_coupon,
          invoice: other_invoice,
          amount_cents: 30,
          organization: organization
        )
      end

      before do
        other_invoice.invoice_subscriptions.update(timestamp: current_time, charges_from_datetime: current_time.beginning_of_month,
          charges_to_datetime: current_time.end_of_month)
        credit
      end

      it "returns the amount minus the credit" do
        expect(applied_coupon.remaining_amount_for_this_subscription_billing_period(invoice: invoice)).to eq(70)
      end
    end

    context "when credits exist in non-overlapping billing periods" do
      let(:other_invoice) { create(:invoice, :subscription, customer: customer, organization: organization, subscriptions: [subscription]) }

      before do
        other_invoice.invoice_subscriptions.update(timestamp: current_time, charges_from_datetime: current_time.beginning_of_month - 1.month, charges_to_datetime: current_time.end_of_month - 1.month)
        create(:credit,
          applied_coupon: applied_coupon,
          invoice: other_invoice,
          amount_cents: 40,
          organization: organization
        )
      end

      it "excludes credits from invoices with non-overlapping billing periods" do
        expect(applied_coupon.remaining_amount_for_this_subscription_billing_period(invoice: invoice)).to eq(100)
      end
    end

    context "when credits exceed the original amount" do
      let(:credit) do
        create(:credit,
          applied_coupon: applied_coupon,
          invoice: invoice,
          amount_cents: 150,
          organization: organization
        )
      end

      before do
        credit
      end

      it "returns 0 (never negative)" do
        expect(applied_coupon.remaining_amount_for_this_subscription_billing_period(invoice: invoice)).to eq(0)
      end
    end

    context "when invoice has voided credits" do
      let(:voided_invoice) { create(:invoice, :subscription, status: :voided, customer: customer, organization: organization, subscriptions: [subscription]) }

      before do
        voided_invoice.invoice_subscriptions.update(timestamp: current_time, charges_from_datetime: current_time.beginning_of_month, charges_to_datetime: current_time.end_of_month)
        create(:credit,
          applied_coupon: applied_coupon,
          invoice: voided_invoice,
          amount_cents: 50,
          organization: organization
        )
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
          timestamp: current_time + 1.day,
          charges_from_datetime: (current_time + 1.day).beginning_of_month,
          charges_to_datetime: (current_time + 1.day).end_of_month
        )
      end

      # this credit is associated to subscription 1 and subscription 2
      before do
        invoice_subscription_2
        create(:credit,
          applied_coupon: applied_coupon,
          invoice: invoice,
          amount_cents: 20,
          organization: organization
        )
      end

      it "calculates based on the minimum used amount across all subscriptions" do
        expect(applied_coupon.remaining_amount_for_this_subscription_billing_period(invoice: invoice)).to eq(80)
      end

      context "when each subscription has different remaining amount of the coupon" do
        let(:invoice_2) { create(:invoice, :subscription, customer: customer, organization: organization, subscriptions: [subscription_2]) }

        # this credit is associated only to subscription 2
        let(:credit_2) { create(:credit, applied_coupon: applied_coupon, invoice: invoice_2, amount_cents: 30, organization: organization) }

        before do
          invoice_2.invoice_subscriptions.update(timestamp: current_time, charges_from_datetime: current_time.beginning_of_month, charges_to_datetime: current_time.end_of_month)
          credit_2
        end

        # Note: subscription_2 has 50 credits, becasue it's associated to invoice and invoice_2,
        # but subscription has 20 credits, so the remaining amount is 80
        it "calculates based on the minimum used amount across all subscriptions" do
          invoice.reload
          expect(applied_coupon.remaining_amount_for_this_subscription_billing_period(invoice: invoice)).to eq(80)
        end
      end

      context "when one of subscription has no usage" do
        let(:subscription_3) { create(:subscription, customer: customer, organization: organization) }
        let(:invoice_3) { create(:invoice, :subscription, customer: customer, organization: organization, subscriptions: [subscription_3, subscription_2]) }

        before do
          invoice_3.invoice_subscriptions.update(timestamp: current_time, charges_from_datetime: current_time.beginning_of_month, charges_to_datetime: current_time.end_of_month)
        end

        it "calculates based on the minimum used amount across all subscriptions" do
          expect(applied_coupon.remaining_amount_for_this_subscription_billing_period(invoice: invoice_3)).to eq(100)
        end
      end
    end
  end
end
