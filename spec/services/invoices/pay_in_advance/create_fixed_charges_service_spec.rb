# frozen_string_literal: true

require "rails_helper"
require_relative "shared_examples/pay_in_advance_invoice"

RSpec.describe Invoices::PayInAdvance::CreateFixedChargesService do
  subject(:invoice_service) do
    described_class.new(subscription:, timestamp: timestamp.to_i)
  end

  include_context "with pay_in_advance_invoice_setup"

  let(:add_on) { create(:add_on, organization:) }
  let(:subscription) { create(:subscription, customer:, plan:, status: :active) }
  let(:fixed_charge) { create(:fixed_charge, :pay_in_advance, plan:, add_on:, units: 10, properties: {amount: "10"}) }

  let(:fixed_charge_event) do
    create(
      :fixed_charge_event,
      subscription:,
      fixed_charge:,
      units: 10,
      timestamp: Time.zone.at(timestamp)
    )
  end

  before do
    fixed_charge_event
  end

  describe "#call" do
    let(:service_call) { invoice_service.call }

    before do
      allow(Invoices::TransitionToFinalStatusService).to receive(:call).and_call_original
    end

    it "creates an invoice with fixed charge fees" do
      result = invoice_service.call

      expect(result).to be_success
      expect(result.invoice.issuing_date.to_date).to eq(timestamp.to_date)
      expect(result.invoice.payment_due_date.to_date).to eq(timestamp.to_date)
      expect(result.invoice.organization_id).to eq(organization.id)
      expect(result.invoice.customer_id).to eq(customer.id)
      expect(result.invoice.invoice_type).to eq("subscription")
      expect(result.invoice.payment_status).to eq("pending")
      expect(result.invoice.fees.count).to eq(1)
      expect(result.invoice.fees.first).to have_attributes(
        subscription:,
        fixed_charge:,
        amount_currency: "EUR",
        fee_type: "fixed_charge",
        pay_in_advance: true,
        invoiceable: fixed_charge,
        units: 10,
        payment_status: "pending",
        unit_amount_cents: 1000,
        precise_unit_amount: 10.0
      )
      expect(result.invoice.currency).to eq(customer.currency)
      expect(result.invoice.fees_amount_cents).to eq(10000)
      expect(result.invoice.sub_total_excluding_taxes_amount_cents).to eq(10000)
      expect(result.invoice.taxes_amount_cents).to eq(2000) # factory default 20% tax
      expect(result.invoice.total_amount_cents).to eq(12000) # fees + taxes

      expect(Invoices::TransitionToFinalStatusService).to have_received(:call).with(invoice: result.invoice)
      expect(result.invoice).to be_finalized
    end

    it_behaves_like "pay_in_advance_invoice_post_creation"
    it_behaves_like "pay_in_advance_premium_email_settings"
    it_behaves_like "pay_in_advance_customer_timezone"
    it_behaves_like "pay_in_advance_grace_period"
    it_behaves_like "pay_in_advance_error_handling"
    it_behaves_like "pay_in_advance_concurrent_lock", "Invoices::PayInAdvance::CreateFixedChargesService"
    it_behaves_like "pay_in_advance_integration_sync"

    it_behaves_like "applies invoice_custom_sections" do
      let(:service_call) { invoice_service.call }
    end

    context "when subscription is not active" do
      let(:subscription) { create(:subscription, customer:, plan:, status: :pending) }

      it "returns early without creating an invoice" do
        result = invoice_service.call

        expect(result).to be_success
        expect(result.invoice).to be_nil
      end
    end

    context "when there are no fixed charge events" do
      let(:fixed_charge_event) { nil }

      it "returns early without creating an invoice" do
        result = invoice_service.call

        expect(result).to be_success
        expect(result.invoice).to be_nil
      end
    end

    context "when the fixed charge is not pay_in_advance" do
      let(:fixed_charge) { create(:fixed_charge, plan:, add_on:, pay_in_advance: false) }

      it "returns early without creating an invoice" do
        result = invoice_service.call

        expect(result).to be_success
        expect(result.invoice).to be_nil
      end
    end

    context "with multiple fixed charge events" do
      let(:add_on2) { create(:add_on, organization:) }
      let(:fixed_charge2) { create(:fixed_charge, :pay_in_advance, plan:, add_on: add_on2, units: 5, properties: {amount: "20"}) }
      let(:fixed_charge_event2) do
        create(
          :fixed_charge_event,
          subscription:,
          fixed_charge: fixed_charge2,
          units: 5,
          timestamp: Time.zone.at(timestamp)
        )
      end

      before { fixed_charge_event2 }

      it "creates fees for all fixed charge events" do
        result = invoice_service.call

        expect(result).to be_success
        expect(result.invoice.fees.fixed_charge.count).to eq(2)
      end
    end

    context "when invoice total_amount_cents is zero" do
      let(:customer) { create(:customer, organization:, finalize_zero_amount_invoice: "skip") }

      let(:fixed_charge_event) do
        create(
          :fixed_charge_event,
          subscription:,
          fixed_charge:,
          units: 0,
          timestamp: Time.zone.at(timestamp)
        )
      end

      it "creates an invoice with succeeded payment status" do
        result = invoice_service.call

        expect(result).to be_success
        expect(result.invoice.fees.count).to eq(1)
        expect(result.invoice.total_amount_cents).to eq(0)
        expect(result.invoice).to be_closed
        expect(result.invoice.payment_status).to eq("succeeded")
      end

      it "does not create payments" do
        allow(Invoices::Payments::CreateService).to receive(:call_async)

        result = invoice_service.call

        expect(result).to be_success
        expect(Invoices::Payments::CreateService).not_to have_received(:call_async)
      end

      it "does not enqueue SendWebhookJob" do
        expect do
          invoice_service.call
        end.not_to have_enqueued_job(SendWebhookJob).with("invoice.created", anything)
      end
    end

    context "with credit note credits" do
      let(:credit_note) do
        create(
          :credit_note,
          customer:,
          balance_amount_cents: 500,
          credit_amount_cents: 500,
          status: :finalized,
          credit_status: :available
        )
      end

      before { credit_note }

      it "applies credit note credits to the invoice" do
        result = invoice_service.call

        expect(result).to be_success
        expect(result.invoice.credits.first.credit_note).to eq(credit_note)
        expect(result.invoice.credit_notes_amount_cents).to eq(500)
        expect(result.invoice.total_amount_cents).to eq(11500)
      end
    end

    context "with active wallet" do
      let(:wallet) do
        create(:wallet, customer:, balance_cents: 1000, credits_balance: 10.0)
      end

      before { wallet }

      it "applies prepaid credits to the invoice" do
        result = invoice_service.call

        expect(result).to be_success
        expect(result.invoice.wallet_transactions.first.wallet).to eq(wallet)
        expect(result.invoice.prepaid_credit_amount_cents).to eq(1000)
        expect(result.invoice.total_amount_cents).to eq(11000)
      end
    end

    context "with wallet having zero balance" do
      let(:wallet) { create(:wallet, customer:, balance_cents: 0, credits_balance: 0) }

      before { wallet }

      it "does not apply prepaid credits" do
        result = invoice_service.call

        expect(result).to be_success
        expect(result.invoice.wallet_transactions).to be_empty
        expect(result.invoice.prepaid_credit_amount_cents).to eq(0)
        expect(result.invoice.total_amount_cents).to eq(12000)
      end
    end

    context "with applied coupons" do
      let(:coupon) { create(:coupon, organization:, amount_cents: 500, coupon_type: :fixed_amount) }
      let(:applied_coupon) { create(:applied_coupon, coupon:, customer:, amount_cents: 500) }

      before { applied_coupon }

      it "applies coupons to the invoice" do
        result = invoice_service.call

        expect(result).to be_success
        expect(result.invoice.coupons_amount_cents).to eq(500)
        expect(result.invoice.sub_total_excluding_taxes_amount_cents).to eq(9500) # 10000 - 500 coupon
        expect(result.invoice.total_amount_cents).to eq(11400)
      end
    end

    context "when fee build service fails" do
      before do
        allow(Fees::BuildPayInAdvanceFixedChargeService)
          .to receive(:call)
          .and_return(BaseService::Result.new.service_failure!(code: "code", message: "message"))
      end

      it "fails with a service failure" do
        result = invoice_service.call

        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::ServiceFailure)
        expect(result.error.code).to eq("code")
        expect(result.error.message).to eq("code: message")
      end
    end

    context "with graduated fixed charge model" do
      let(:fixed_charge) do
        create(
          :fixed_charge,
          :graduated,
          :pay_in_advance,
          plan:,
          add_on:
        )
      end

      let(:fixed_charge_event) do
        create(
          :fixed_charge_event,
          subscription:,
          fixed_charge:,
          units: 12,
          timestamp: Time.zone.at(timestamp)
        )
      end

      it "creates an invoice with graduated pricing" do
        result = invoice_service.call

        expect(result).to be_success
        expect(result.invoice.fees.count).to eq(1)
        # 10 units * 5 + 200 flat = 250
        # 2 units * 1 + 300 flat = 302
        # total = 552
        expect(result.invoice.fees.fixed_charge.first.amount_cents).to eq(55200)
        # 55200 / 12 = 4600
        expect(result.invoice.fees.fixed_charge.first.unit_amount_cents).to eq(4600)
        expect(result.invoice.fees.fixed_charge.first.units).to eq(12)
      end
    end

    context "with prorated fixed charge" do
      let(:plan) { create(:plan, organization:, interval: "monthly") }
      let(:subscription) do
        create(
          :subscription,
          customer:,
          plan:,
          status: :active,
          billing_time: "calendar",
          started_at: Time.zone.parse("2025-05-01"),
          subscription_at: Time.zone.parse("2025-05-01")
        )
      end
      let(:timestamp) { Time.zone.parse("2025-05-20").to_i }
      let(:fixed_charge) do
        create(
          :fixed_charge,
          :pay_in_advance,
          prorated: true,
          plan:,
          add_on:,
          units: 6,
          properties: {amount: "31"}
        )
      end

      let(:fixed_charge_fee) do
        create(
          :fixed_charge_fee,
          organization:,
          subscription:,
          fixed_charge:,
          units: 6,
          properties: {
            "fixed_charges_from_datetime" => subscription.started_at,
            "fixed_charges_to_datetime" => subscription.started_at.end_of_month
          }
        )
      end

      let(:fixed_charge_event) do
        create(
          :fixed_charge_event,
          subscription:,
          fixed_charge:,
          units: 7,
          timestamp: Time.zone.at(timestamp)
        )
      end

      before { fixed_charge_fee }

      it "creates an invoice with prorated pricing" do
        result = invoice_service.call

        expect(result).to be_success
        expect(result.invoice.fees.count).to eq(1)
        # (7 units - 6 units) = 1 unit to prorate
        # 1 unit * (12 / 31) = 0.3870967741935484 prorated units
        # 0.3870967741935484 * 31 = 12.000000000000002 amount
        expect(result.invoice.fees.fixed_charge.first.amount_cents).to eq(1200)
        expect(result.invoice.fees.fixed_charge.first.precise_amount_cents.round(4)).to eq(1200.0)
        expect(result.invoice.fees.fixed_charge.first.units).to eq(1)
      end
    end

    context "when fixed charge event timestamp does not match" do
      let(:fixed_charge_event) do
        create(
          :fixed_charge_event,
          subscription:,
          fixed_charge:,
          units: 10,
          timestamp: Time.zone.at(timestamp) + 1.day
        )
      end

      it "returns early without creating an invoice" do
        result = invoice_service.call

        expect(result).to be_success
        expect(result.invoice).to be_nil
      end
    end

    context "when subscription has a terminated status" do
      let(:subscription) { create(:subscription, customer:, plan:, status: :terminated) }

      it "returns early without creating an invoice" do
        result = invoice_service.call

        expect(result).to be_success
        expect(result.invoice).to be_nil
      end
    end

    context "when subscription has a canceled status" do
      let(:subscription) { create(:subscription, customer:, plan:, status: :canceled) }

      it "returns early without creating an invoice" do
        result = invoice_service.call

        expect(result).to be_success
        expect(result.invoice).to be_nil
      end
    end

    context "with record validation failure" do
      before do
        allow(Fee).to receive(:new).and_return(
          Fee.new.tap do |fee|
            fee.errors.add(:base, "test error")
            allow(fee).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(fee))
          end
        )
      end

      it "returns a validation failure result" do
        result = invoice_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
      end
    end
  end
end
