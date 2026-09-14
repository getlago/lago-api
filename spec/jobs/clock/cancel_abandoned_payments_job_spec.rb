# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clock::CancelAbandonedPaymentsJob, job: true do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }

  let!(:abandoned) { abandoned_payment(updated_at: 25.hours.ago) }
  let!(:recent) { abandoned_payment(updated_at: 1.hour.ago) }
  let!(:settled) { abandoned_payment(updated_at: 25.hours.ago, payable_payment_status: "succeeded") }
  let!(:not_challenged) { abandoned_payment(updated_at: 25.hours.ago, status: "processing") }

  def abandoned_payment(updated_at:, **attributes)
    invoice = create(:invoice, customer:, organization:)
    create(
      :payment,
      :requires_action,
      payable: invoice,
      customer:,
      organization:,
      payable_payment_status: "processing",
      updated_at:,
      **attributes
    )
  end

  describe ".perform" do
    it "enqueues the cancellation job only for authentication challenges past the abandon period" do
      described_class.perform_now

      expect(Invoices::Payments::CancelAbandonedJob).to have_been_enqueued.with(abandoned)
      expect(Invoices::Payments::CancelAbandonedJob).not_to have_been_enqueued.with(recent)
      expect(Invoices::Payments::CancelAbandonedJob).not_to have_been_enqueued.with(settled)
      expect(Invoices::Payments::CancelAbandonedJob).not_to have_been_enqueued.with(not_challenged)
    end

    it "leaves a payment waiting on an incoming bank transfer alone" do
      payment = create(
        :payment,
        :awaiting_bank_transfer,
        payable: create(:invoice, customer:, organization:),
        customer:,
        organization:,
        payable_payment_status: "processing",
        updated_at: 25.hours.ago
      )

      described_class.perform_now

      expect(Invoices::Payments::CancelAbandonedJob).not_to have_been_enqueued.with(payment)
    end

    it "ignores payments that are not attached to an invoice" do
      payment = create(
        :payment,
        :requires_action,
        payable: create(:payment_request, customer:, organization:),
        customer:,
        organization:,
        payable_payment_status: "processing",
        updated_at: 25.hours.ago
      )

      described_class.perform_now

      expect(Invoices::Payments::CancelAbandonedJob).not_to have_been_enqueued.with(payment)
    end
  end
end
