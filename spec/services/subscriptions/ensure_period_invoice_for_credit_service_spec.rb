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

  def bill_period_invoice(status:)
    create(:invoice_subscription,
      subscription:,
      invoice: create(:invoice, customer:, organization:, status:),
      recurring: true, from_datetime: 1.day.ago, to_datetime: 1.month.from_now)
  end

  context "when the plan is pay in advance" do
    context "when the period has a usable invoice" do
      before { bill_period_invoice(status: :finalized) }

      it "returns success" do
        expect(result).to be_success
      end
    end

    context "when the period has no usable invoice" do
      it "raises MissingCreditableInvoiceError" do
        expect { result }.to raise_error(described_class::MissingCreditableInvoiceError)
      end
    end

    context "when the period invoice is voided" do
      before { bill_period_invoice(status: :voided) }

      it "raises MissingCreditableInvoiceError" do
        expect { result }.to raise_error(described_class::MissingCreditableInvoiceError)
      end
    end

    context "when the period invoice is still generating" do
      before { bill_period_invoice(status: :generating) }

      it "returns success" do
        expect(result).to be_success
      end
    end
  end

  context "when the plan is pay in arrears" do
    let(:plan) { create(:plan, organization:, pay_in_advance: false) }

    it "returns success without verifying the period" do
      expect(result).to be_success
    end
  end

  context "when the subscription opts out of the termination credit note" do
    let(:subscription) do
      create(:subscription, organization:, customer:, plan:, status: :active,
        started_at: 1.month.ago, subscription_at: 1.month.ago, on_termination_credit_note: :skip)
    end

    it "returns success without verifying the period" do
      expect(result).to be_success
    end
  end
end
