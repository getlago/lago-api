# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::CloseDisputeService do
  subject(:close_dispute_service) { described_class.new(payment:) }

  describe "#call" do
    context "when payment does not exist" do
      let(:payment) { nil }

      it "returns a not found failure" do
        result = close_dispute_service.call

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
        result = close_dispute_service.call

        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("payable")
      end
    end

    context "when payable is an invoice" do
      let(:invoice) { create(:invoice, :refund_blocked, status: "finalized", payment_status: "succeeded") }
      let(:payment) { create(:payment, payable: invoice) }

      it "clears the dispute flag" do
        expect { close_dispute_service.call && invoice.reload }
          .to change(invoice, :payment_refund_blocked_at).to(nil)
      end

      it "returns the payment and the invoices" do
        result = close_dispute_service.call

        expect(result).to be_success
        expect(result.payment).to eq(payment)
        expect(result.invoices).to eq([invoice])
      end

      it "does not enqueue a send webhook job" do
        expect { close_dispute_service.call }.not_to have_enqueued_job(SendWebhookJob)
      end

      context "when refunds are not blocked" do
        let(:invoice) { create(:invoice, status: "finalized", payment_status: "succeeded") }

        it "leaves the invoice untouched" do
          expect { close_dispute_service.call && invoice.reload }
            .not_to change(invoice, :payment_refund_blocked_at).from(nil)
        end
      end
    end

    context "when payable is a payment request" do
      let(:organization) { create(:organization) }
      let(:customer) { create(:customer, organization:) }
      let(:invoice_1) do
        create(:invoice, :refund_blocked, customer:, organization:, status: "finalized", payment_status: "succeeded")
      end
      let(:invoice_2) do
        create(:invoice, :refund_blocked, customer:, organization:, status: "finalized", payment_status: "succeeded")
      end
      let(:payment_request) { create(:payment_request, customer:, organization:, invoices: [invoice_1, invoice_2]) }
      let(:payment) { create(:payment, payable: payment_request) }

      it "clears the flag on every invoice of the payment request" do
        close_dispute_service.call

        expect(invoice_1.reload.payment_refund_blocked_at).to be_nil
        expect(invoice_2.reload.payment_refund_blocked_at).to be_nil
      end
    end
  end
end
