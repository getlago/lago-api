# frozen_string_literal: true

require "rails_helper"

describe Subscriptions::EnsurePeriodInvoiceForCreditService do
  subject(:result) { described_class.call(subscription:, timestamp:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, pay_in_advance: true) }
  let(:subscription) do
    create(:subscription, organization:, customer:, plan:, status: :active,
      started_at: 1.month.ago, subscription_at: 1.month.ago)
  end
  let(:timestamp) { Time.current }
  let(:issued) { true }

  before do
    allow(Subscriptions::PayInAdvanceInvoiceIssuedService).to receive(:call)
      .and_return(Subscriptions::PayInAdvanceInvoiceIssuedService::Result.new.tap { |r| r.issued = issued })
  end

  context "when the plan is pay in advance" do
    context "when the period invoice was issued and is creditable" do
      it "returns success" do
        expect(result).to be_success
      end
    end

    context "when the pay-in-advance invoice was not issued" do
      let(:issued) { false }

      it "raises MissingCreditableInvoiceError with recovery instructions" do
        expect { result }.to raise_error(
          described_class::MissingCreditableInvoiceError,
          "subscription #{subscription.id} has no usable invoice for the period at #{timestamp.iso8601}: " \
          "BillSubscriptionJob must finish successfully and produce the period invoice before " \
          "Subscriptions::ActivationRules::Payment::ResolveJob is re-executed"
        )
      end
    end

    context "when the period invoice is voided" do
      before do
        voided_invoice = create(:invoice, customer:, organization:, status: :voided)
        create(:fee, subscription:, invoice: voided_invoice, amount_cents: 1000)
      end

      it "raises MissingCreditableInvoiceError with recovery instructions" do
        expect { result }.to raise_error(
          described_class::MissingCreditableInvoiceError,
          "subscription #{subscription.id} has no usable invoice for the period at #{timestamp.iso8601}: " \
          "BillSubscriptionJob must finish successfully and produce the period invoice before " \
          "Subscriptions::ActivationRules::Payment::ResolveJob is re-executed"
        )
      end
    end
  end

  context "when the plan is pay in arrears" do
    let(:plan) { create(:plan, organization:, pay_in_advance: false) }

    it "returns success" do
      expect(result).to be_success
    end
  end

  context "when the subscription opts out of the termination credit note" do
    let(:subscription) do
      create(:subscription, organization:, customer:, plan:, status: :active,
        started_at: 1.month.ago, subscription_at: 1.month.ago, on_termination_credit_note: :skip)
    end

    it "returns success" do
      expect(result).to be_success
    end
  end
end
