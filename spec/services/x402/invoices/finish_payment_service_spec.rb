# frozen_string_literal: true

require "rails_helper"

describe X402::Invoices::FinishPaymentService do
  subject(:result) { described_class.call(settlement:, transaction_hash:) }

  let(:organization) { create(:organization) }
  let(:x402_connection) { create(:x402_connection, organization:) }
  let(:invoice) { create(:invoice, organization:, currency: "USD", total_amount_cents: 100) }
  let(:settlement) { create(:x402_settlement, :pending, :invoice_payment, x402_connection:, invoice:) }
  let(:transaction_hash) { "0x#{"ef" * 32}" }

  before do
    allow(Sentry).to receive(:capture_exception)
    allow(Rails.logger).to receive(:warn)
  end

  it "marks the attempt settled" do
    expect(result.settlement.reload).to have_attributes(status: "settled", transaction_hash:)
  end

  it "records the x402 payment" do
    expect(result.payment).to have_attributes(payment_type: "x402", amount_cents: 100, payable: invoice, payable_payment_status: "succeeded")
  end

  it "links the payment on the attempt" do
    expect(result.settlement.reload.payment).to eq(result.payment)
  end

  it "marks the invoice paid" do
    result

    expect(invoice.reload).to have_attributes(payment_status: "succeeded", total_paid_amount_cents: 100)
  end

  it "notifies the merchant once" do
    expect { result }.to have_enqueued_job(SendWebhookJob).with("invoice.payment_status_updated", invoice).once
  end

  it "sends payment.succeeded once" do
    expect { result }.to have_enqueued_job(SendWebhookJob).with("payment.succeeded", instance_of(Payment)).once
  end

  context "with a credit invoice" do
    let(:invoice) { create(:invoice, :credit, organization:, currency: "USD", total_amount_cents: 100) }

    it "runs the paid-credit path" do
      expect { result }.to have_enqueued_job(Invoices::PrepaidCreditJob).with(invoice, :succeeded)
    end
  end

  context "when the payment cannot be recorded" do
    let(:invoice) { create(:invoice, organization:, currency: "USD", total_amount_cents: 50) }

    it "keeps the attempt settled" do
      expect(result.settlement.reload).to have_attributes(status: "settled", payment_id: nil)
    end

    it "leaves the invoice unpaid" do
      result

      expect(invoice.reload.payment_status).to eq("pending")
    end

    it "reports the failure" do
      result

      expect(Sentry).to have_received(:capture_exception).with(
        instance_of(BaseService::ValidationFailure),
        extra: {organization_id: organization.id, settlement_id: settlement.id, network: "eip155:84532"}
      )
    end
  end

  context "with a settled attempt" do
    let(:settlement) { create(:x402_settlement, :invoice_payment, x402_connection:, invoice:) }

    it "keeps its transaction" do
      expect { result }.not_to change { settlement.reload.transaction_hash }
    end

    it "records the payment" do
      expect(result.payment).to be_present
    end
  end

  context "with a failed attempt" do
    let(:settlement) { create(:x402_settlement, :failed, :invoice_payment, x402_connection:, invoice:) }

    it "records nothing" do
      expect { result }.not_to change(Payment, :count)
    end
  end

  context "with the transaction held by another attempt" do
    before { create(:x402_settlement, x402_connection:, transaction_hash:) }

    it "raises" do
      expect { result }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "leaves the attempt pending" do
      expect { result }.to raise_error(ActiveRecord::RecordNotUnique)
      expect(settlement.reload).to be_pending
    end
  end
end
