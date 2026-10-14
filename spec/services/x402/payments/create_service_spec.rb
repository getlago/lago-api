# frozen_string_literal: true

require "rails_helper"

describe X402::Payments::CreateService, :premium do
  subject(:result) { described_class.call(settlement:, invoice:) }

  let(:organization) { create(:organization, premium_integrations: %w[issue_receipts]) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, :credit, organization:, customer:, currency: "USD", total_amount_cents: 1000) }
  let(:x402_connection) { create(:x402_connection, organization:) }
  let(:subscription) { create(:subscription, customer:) }
  let(:wallet_transaction) { create(:wallet_transaction, wallet: create(:wallet, customer:), source: :x402, invoice:) }
  let(:settlement) do
    create(:x402_settlement, x402_connection:, customer:, subscription:, wallet_transaction:, settled_amount_atomic: 10_000_000, settled_amount_cents: 1000)
  end

  it "records a succeeded x402 payment for the settled amount" do
    expect(result.payment).to have_attributes(
      payable: invoice,
      organization_id: organization.id,
      customer_id: customer.id,
      payment_type: "x402",
      amount_cents: 1000,
      amount_currency: "USD",
      status: "succeeded",
      payable_payment_status: "succeeded",
      payment_provider_id: nil,
      provider_payment_id: nil,
      reference: nil
    )
  end

  it "links the payment on the settlement" do
    expect(result.payment.reload.x402_settlement).to eq(settlement)
  end

  it "marks the invoice as paid" do
    expect { result }
      .to change { invoice.reload.payment_status }.from("pending").to("succeeded")
      .and change { invoice.reload.total_paid_amount_cents }.from(0).to(1000)
  end

  it "notifies the payment status after commit" do
    expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("invoice.payment_status_updated", invoice)
  end

  it "notifies the payment after commit" do
    expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("payment.succeeded", instance_of(Payment))
  end

  it "settles the prepaid credits after commit" do
    expect { result }.to have_enqueued_job_after_commit(Invoices::PrepaidCreditJob).with(invoice, :succeeded)
  end

  it "issues the receipt after commit" do
    expect { result }.to have_enqueued_job_after_commit(PaymentReceipts::CreateJob).with(instance_of(Payment))
  end

  context "without receipts" do
    let(:organization) { create(:organization) }

    it "marks the invoice as paid" do
      expect { result }.to change { invoice.reload.payment_status }.from("pending").to("succeeded")
    end

    it "issues no receipt" do
      expect { result }.not_to have_enqueued_job(PaymentReceipts::CreateJob)
    end
  end

  context "with an accounting integration that syncs payments" do
    let(:integration) do
      create(
        :netsuite_integration,
        organization:,
        settings: {
          account_id: "acc_12345",
          client_id: "cli_12345",
          script_endpoint_url: Faker::Internet.url,
          sync_payments: true
        }
      )
    end

    before { create(:netsuite_customer, integration:, customer:) }

    it "syncs the payment after commit" do
      expect { result }.to have_enqueued_job_after_commit(Integrations::Aggregator::Payments::CreateJob).with(payment: instance_of(Payment))
    end
  end

  context "when the settlement already has its payment" do
    let(:payment) { described_class.call!(settlement:, invoice:).payment }

    before { payment }

    it "returns that payment" do
      expect(result.payment).to eq(payment)
    end

    it "records no other payment" do
      expect { result }.not_to change(Payment, :count)
    end

    it "issues no other receipt" do
      expect { result }.not_to have_enqueued_job(PaymentReceipts::CreateJob)
    end
  end

  context "when the settlement paid another invoice" do
    let(:paid_invoice) { create(:invoice, :credit, organization:, customer:, currency: "USD", total_amount_cents: 1000) }
    let(:payment) do
      create(
        :payment,
        payable: paid_invoice,
        payment_type: :x402,
        payment_provider: nil,
        payment_provider_customer: nil,
        provider_payment_id: nil,
        amount_cents: 1000,
        amount_currency: "USD",
        status: "succeeded",
        payable_payment_status: "succeeded"
      )
    end
    let(:settlement) do
      create(
        :x402_settlement,
        x402_connection:,
        customer:,
        subscription:,
        wallet_transaction:,
        payment:,
        settled_amount_atomic: 10_000_000,
        settled_amount_cents: 1000
      )
    end

    it "refuses the invoice" do
      expect(result.error.messages).to eq(base: ["settlement_invoice_mismatch"])
    end
  end

  context "when the purchase is billed on another invoice" do
    let(:wallet_transaction) do
      create(:wallet_transaction, wallet: create(:wallet, customer:), source: :x402, invoice: create(:invoice, :credit, organization:, customer:))
    end

    it "refuses the invoice" do
      expect(result.error.messages).to eq(base: ["settlement_invoice_mismatch"])
    end

    it "records no payment" do
      expect { result }.not_to change(Payment, :count)
    end
  end

  context "when the purchase is not granted" do
    let(:settlement) do
      create(:x402_settlement, x402_connection:, customer:, settled_amount_atomic: 10_000_000, settled_amount_cents: 1000)
    end

    it "refuses the invoice" do
      expect(result.error.messages).to eq(base: ["settlement_invoice_mismatch"])
    end
  end

  context "when the settlement is still pending" do
    let(:settlement) do
      create(:x402_settlement, :pending, x402_connection:, customer:, settled_amount_atomic: 10_000_000, settled_amount_cents: 1000)
    end

    it "refuses to record a payment" do
      expect(result.error.messages).to eq(base: ["settlement_not_settled"])
    end

    it "leaves the invoice unpaid" do
      expect { result }.not_to change { invoice.reload.payment_status }
    end
  end

  context "when the settled amount differs from the invoice total" do
    let(:settlement) do
      create(:x402_settlement, x402_connection:, customer:, subscription:, wallet_transaction:, settled_amount_atomic: 9_990_000, settled_amount_cents: 999)
    end

    it "refuses the amount" do
      expect(result.error.messages).to eq(amount_cents: ["invalid_amount"])
    end

    it "leaves the invoice unpaid" do
      expect { result }.not_to change { invoice.reload.payment_status }
    end

    it "leaves the settlement without a payment" do
      expect { result }.not_to change { settlement.reload.payment_id }.from(nil)
    end
  end

  context "with a draft invoice" do
    let(:invoice) { create(:invoice, :credit, :draft, organization:, customer:, currency: "USD", total_amount_cents: 1000) }

    it "fails on the payment status" do
      expect(result.error).to have_attributes(class: BaseService::MethodNotAllowedFailure, code: "payment_status_update_on_draft_invoice")
    end

    it "rolls the payment back" do
      expect { result }.not_to change(Payment, :count)
    end

    it "leaves the settlement without a payment" do
      expect(result.payment).to be_nil
      expect(settlement.payment_id).to be_nil
    end

    it "leaves nothing to save on the invoice" do
      result

      expect(invoice).not_to be_changed
      expect(invoice.payments).to be_empty
    end

    context "when the caller holds a transaction" do
      it "rolls the payment back" do
        ActiveRecord::Base.transaction do
          expect { result }.not_to change(Payment, :count)
          expect(settlement.reload.payment_id).to be_nil
        end
      end
    end
  end

  context "with an invoice payment" do
    let(:invoice) { create(:invoice, organization:, customer:, currency: "USD", total_amount_cents: 1000) }
    let(:settlement) do
      create(:x402_settlement, :invoice_payment, x402_connection:, invoice:, settled_amount_atomic: 10_000_000, settled_amount_cents: 1000)
    end

    it "marks the invoice as paid" do
      expect { result }.to change { invoice.reload.payment_status }.from("pending").to("succeeded")
    end

    it "leaves prepaid credits alone" do
      expect { result }.not_to have_enqueued_job(Invoices::PrepaidCreditJob)
    end

    context "when the settlement pays another invoice" do
      let(:settlement) do
        create(:x402_settlement, :invoice_payment, x402_connection:, settled_amount_atomic: 10_000_000, settled_amount_cents: 1000)
      end

      it "refuses the invoice" do
        expect(result.error.messages).to eq(base: ["settlement_invoice_mismatch"])
      end

      it "records no payment" do
        expect { result }.not_to change(Payment, :count)
      end
    end
  end
end
