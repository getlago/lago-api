# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::OpenDisputeService do
  subject(:open_dispute_service) { described_class.new(payment:, payment_refund_blocked_at:) }

  let(:payment_refund_blocked_at) { 1.day.ago.change(usec: 0) }

  describe "#call" do
    context "when payment does not exist" do
      let(:payment) { nil }

      it "returns a not found failure" do
        result = open_dispute_service.call

        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("payment")
      end
    end

    context "when payable is not found" do
      let(:payment) { create(:payment, payable: create(:payment_request)) }

      before do
        payment.payable.destroy!
        payment.reload
      end

      it "returns a not found failure" do
        result = open_dispute_service.call

        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("payable")
      end
    end

    context "when payable is an invoice" do
      let(:invoice) { create(:invoice, status: "finalized", payment_status: "succeeded") }
      let(:payment) { create(:payment, payable: invoice) }

      it "blocks refunds on the invoice" do
        expect { open_dispute_service.call && invoice.reload }
          .to change(invoice, :payment_refund_blocked_at).from(nil).to(payment_refund_blocked_at)
      end

      it "returns the payment and the invoices" do
        result = open_dispute_service.call

        expect(result).to be_success
        expect(result.payment).to eq(payment)
        expect(result.invoices).to eq([invoice])
      end

      it "does not enqueue a send webhook job" do
        expect { open_dispute_service.call }.not_to have_enqueued_job(SendWebhookJob)
      end

      it "keeps the first timestamp when called twice" do
        open_dispute_service.call
        invoice.reload

        expect { described_class.call(payment:, payment_refund_blocked_at: Time.current) && invoice.reload }
          .not_to change(invoice, :payment_refund_blocked_at).from(payment_refund_blocked_at)
      end

      context "when the dispute was already lost" do
        let(:invoice) { create(:invoice, :dispute_lost, status: "finalized", payment_status: "succeeded") }

        it "does not block refunds on the invoice" do
          expect { open_dispute_service.call && invoice.reload }
            .not_to change(invoice, :payment_refund_blocked_at).from(nil)
        end
      end
    end

    context "when payable is a payment request" do
      let(:organization) { create(:organization) }
      let(:customer) { create(:customer, organization:) }
      let(:invoice_1) { create(:invoice, customer:, organization:, status: "finalized", payment_status: "succeeded") }
      let(:invoice_2) { create(:invoice, customer:, organization:, status: "finalized", payment_status: "succeeded") }
      let(:payment_request) { create(:payment_request, customer:, organization:, invoices: [invoice_1, invoice_2]) }
      let(:payment) { create(:payment, payable: payment_request) }

      it "flags every invoice of the payment request" do
        open_dispute_service.call

        expect(invoice_1.reload.payment_refund_blocked_at).to eq(payment_refund_blocked_at)
        expect(invoice_2.reload.payment_refund_blocked_at).to eq(payment_refund_blocked_at)
      end
    end
  end
end
