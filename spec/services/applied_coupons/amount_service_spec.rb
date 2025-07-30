# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppliedCoupons::AmountService do
  subject(:amount_service) do
    described_class.new(applied_coupon:, base_amount_cents:, invoice:)
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:base_amount_cents) { 300 }
  let(:coupon) { create(:coupon, organization:) }
  let(:applied_coupon) { create(:applied_coupon, amount_cents: 12, coupon:, customer:) }
  let(:invoice) { create(:invoice, customer:, organization:) }
  let(:invoice_subscription) { create(:invoice_subscription, invoice:, timestamp: invoice.issuing_date, charges_to_datetime: invoice.issuing_date, charges_from_datetime: invoice.issuing_date - 1.month) }
  let(:subscription) { invoice_subscription.subscription }

  describe "call" do
    before do
      invoice_subscription
    end

    it "calculates amount" do
      result = amount_service.call

      expect(result).to be_success
      expect(result.amount).to eq(12)
    end

    context "when base_amount_cents is equal to 0" do
      let(:base_amount_cents) { 0 }

      it "limits the amount to the invoice amount" do
        result = amount_service.call

        expect(result).to be_success
        expect(result.amount).to eq(0)
      end
    end

    context "when coupon amount is higher than invoice amount" do
      let(:base_amount_cents) { 6 }

      it "limits the amount to the invoice amount" do
        result = amount_service.call

        expect(result).to be_success
        expect(result.amount).to eq(6)
      end
    end

    context "when coupon is partially used" do
      before do
        create(
          :credit,
          applied_coupon:,
          amount_cents: 6
        )
      end

      it "applies the remaining amount" do
        result = amount_service.call

        expect(result).to be_success
        expect(result.amount).to eq(6)
      end
    end

    context "when coupon is percentage" do
      let(:coupon) { create(:coupon, coupon_type: "percentage", percentage_rate: 10.00) }

      let(:applied_coupon) do
        create(:applied_coupon, coupon:, percentage_rate: 20.00)
      end

      it "calculates amount" do
        result = amount_service.call

        expect(result).to be_success
        expect(result.amount).to eq(60)
      end
    end

    context "when coupon is recurring and fixed amount" do
      let(:coupon) { create(:coupon, frequency: "recurring", frequency_duration: 3) }

      let(:applied_coupon) do
        create(
          :applied_coupon,
          coupon:,
          frequency: "recurring",
          frequency_duration: 3,
          frequency_duration_remaining: 3,
          amount_cents: 12
        )
      end

      it "calculates amount" do
        result = amount_service.call

        expect(result).to be_success
        expect(result.amount).to eq(12)
      end

      context "when coupon amount is higher than invoice amount" do
        let(:base_amount_cents) { 6 }

        it "limits the amount to the invoice amount" do
          result = amount_service.call

          expect(result).to be_success
          expect(result.amount).to eq(6)
        end
      end

      context "when the coupon was already applied to some invoice" do
        let(:prev_invoice) { create(:invoice, customer:, organization:, issuing_date: 2.weeks.ago) }
        let(:credit) { create(:credit, applied_coupon:, invoice: prev_invoice, amount_cents: 10) }
        let(:prev_invoice_subscription) do
          create(
            :invoice_subscription,
            subscription:,
            invoice: prev_invoice,
            timestamp: prev_invoice.issuing_date,
            charges_to_datetime: invoice.issuing_date,
            charges_from_datetime: invoice.issuing_date - 1.month
          )
        end
        let(:prev_invoice_fee) do
          create(:fee, invoice: prev_invoice, subscription:, amount_cents: 20,
            properties: {charges_from_datetime: prev_invoice_subscription.charges_from_datetime,
                         charges_to_datetime: prev_invoice_subscription.charges_to_datetime})
        end

        before do
          prev_invoice_fee
          credit
        end

        it "calculates the remaining amount" do
          result = amount_service.call

          expect(result).to be_success
          expect(result.amount).to eq(2)
        end

        context "when coupon is completely used" do
          let(:credit) { create(:credit, applied_coupon:, invoice: prev_invoice, amount_cents: 12) }

          it "returns 0" do
            result = amount_service.call

            expect(result).to be_success
            expect(result.amount).to eq(0)
          end
        end

        context "when previous invoice is from another billing period" do
          before do
            prev_invoice_subscription.update(charges_from_datetime: prev_invoice.issuing_date - 2.months, charges_to_datetime: prev_invoice.issuing_date - 1.month)
            prev_invoice_fee.update(properties: {charges_from_datetime: prev_invoice_subscription.charges_from_datetime, charges_to_datetime: prev_invoice_subscription.charges_to_datetime})
          end

          it "calculates the remaining amount" do
            result = amount_service.call

            expect(result).to be_success
            expect(result.amount).to eq(12)
          end
        end
      end
    end

    context "when coupon is forever and fixed amount" do
      let(:coupon) { create(:coupon, frequency: "forever", frequency_duration: 0) }

      let(:applied_coupon) do
        create(
          :applied_coupon,
          coupon:,
          frequency: "forever",
          frequency_duration: 0,
          frequency_duration_remaining: 0,
          amount_cents: 12
        )
      end

      it "calculates amount" do
        result = amount_service.call

        expect(result).to be_success
        expect(result.amount).to eq(12)
      end

      context "when coupon amount is higher than invoice amount" do
        let(:base_amount_cents) { 6 }

        it "limits the amount to the invoice amount" do
          result = amount_service.call

          expect(result).to be_success
          expect(result.amount).to eq(6)
        end
      end
    end

    context "when coupon is recurring and percentage" do
      let(:coupon) do
        create(:coupon, frequency: "recurring", frequency_duration: 3, coupon_type: "percentage", percentage_rate: 10)
      end

      let(:applied_coupon) do
        create(
          :applied_coupon,
          coupon:,
          frequency: "recurring",
          frequency_duration: 3,
          frequency_duration_remaining: 3,
          percentage_rate: 20.00
        )
      end

      it "calculates amount" do
        result = amount_service.call

        expect(result).to be_success
        expect(result.amount).to eq(60)
      end
    end
  end
end
