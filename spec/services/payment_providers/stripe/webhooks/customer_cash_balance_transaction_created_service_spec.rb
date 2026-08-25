# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Stripe::Webhooks::CustomerCashBalanceTransactionCreatedService do
  subject(:webhook_service) { described_class.new(organization_id: organization.id, event:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, currency: "EUR") }
  let(:stripe_provider) { create(:stripe_provider, organization:) }

  let(:provider_payment_methods) { ["customer_balance"] }
  let(:stripe_customer) do
    create(
      :stripe_customer,
      payment_provider: stripe_provider,
      customer:,
      provider_customer_id: "cus_SR8o2vcGRkVb6v",
      provider_payment_methods:
    )
  end

  let(:event) { Stripe::Event.construct_from(JSON.parse(event_json)) }
  let(:event_json) { get_stripe_fixtures("webhooks/customer_cash_balance_transaction_created.json") }

  let(:invoice) do
    create(:invoice, organization:, customer:, currency: "EUR", status: :finalized, payment_status: :failed)
  end

  def create_payment(payable, payable_payment_status, status)
    create(
      :payment,
      payable:,
      customer:,
      payment_provider: stripe_provider,
      payment_provider_customer: stripe_customer,
      payable_payment_status:,
      status:
    )
  end

  before do
    stripe_customer
    create_payment(invoice, :failed, "failed")
    allow(Invoices::Payments::CreateJob).to receive(:perform_later)
  end

  describe "#call" do
    it "opens a payment intent on the invoice whose intent died" do
      result = webhook_service.call

      expect(result).to be_success
      expect(result.invoice).to eq(invoice)
      expect(Invoices::Payments::CreateJob).to have_received(:perform_later)
        .with(invoice:, payment_provider: :stripe)
    end

    context "when several invoices had their intent canceled" do
      let(:older_invoice) do
        create(
          :invoice,
          organization:,
          customer:,
          currency: "EUR",
          status: :finalized,
          payment_status: :failed,
          issuing_date: invoice.issuing_date - 1.month
        )
      end

      before { create_payment(older_invoice, :failed, "failed") }

      it "targets the oldest one" do
        result = webhook_service.call

        expect(result.invoice).to eq(older_invoice)
        expect(Invoices::Payments::CreateJob).to have_received(:perform_later)
          .with(invoice: older_invoice, payment_provider: :stripe)
      end
    end

    context "when only a newer invoice has an awaiting-funds payment open" do
      let(:older_invoice) do
        create(
          :invoice,
          organization:,
          customer:,
          currency: "EUR",
          status: :finalized,
          payment_status: :failed,
          issuing_date: invoice.issuing_date - 1.month
        )
      end

      before do
        create_payment(older_invoice, :failed, "failed")
        create_payment(invoice, :processing, "requires_action")
      end

      it "still opens an intent on the older invoice" do
        result = webhook_service.call

        expect(result.invoice).to eq(older_invoice)
        expect(Invoices::Payments::CreateJob).to have_received(:perform_later)
          .with(invoice: older_invoice, payment_provider: :stripe)
      end
    end

    context "when a new intent already replaced the failed one" do
      before { create_payment(invoice, :processing, "requires_action") }

      it "does not open another intent" do
        result = webhook_service.call

        expect(result).to be_success
        expect(result.invoice).to be_nil
        expect(Invoices::Payments::CreateJob).not_to have_received(:perform_later)
      end
    end

    context "when the invoice never had a payment attempt" do
      let(:invoice) do
        create(:invoice, organization:, customer:, currency: "EUR", status: :finalized, payment_status: :pending)
      end

      before { Payment.where(payable: invoice).delete_all }

      it "does not open an intent" do
        result = webhook_service.call

        expect(result).to be_success
        expect(Invoices::Payments::CreateJob).not_to have_received(:perform_later)
      end
    end

    context "when the customer does not use customer_balance" do
      let(:provider_payment_methods) { %w[card] }

      it "does not open an intent" do
        result = webhook_service.call

        expect(result).to be_success
        expect(Invoices::Payments::CreateJob).not_to have_received(:perform_later)
      end
    end

    context "when the transaction is not a funding" do
      let(:event_json) do
        get_stripe_fixtures("webhooks/customer_cash_balance_transaction_created.json") do |h|
          h[:data][:object][:type] = "applied_to_payment"
        end
      end

      it "does not open an intent" do
        result = webhook_service.call

        expect(result).to be_success
        expect(Invoices::Payments::CreateJob).not_to have_received(:perform_later)
      end
    end

    context "when the funds are already fully allocated" do
      let(:event_json) do
        get_stripe_fixtures("webhooks/customer_cash_balance_transaction_created.json") do |h|
          h[:data][:object][:ending_balance] = 0
        end
      end

      it "does not open an intent" do
        result = webhook_service.call

        expect(result).to be_success
        expect(Invoices::Payments::CreateJob).not_to have_received(:perform_later)
      end
    end

    context "when no unpaid invoice matches the funded currency" do
      let(:event_json) do
        get_stripe_fixtures("webhooks/customer_cash_balance_transaction_created.json") do |h|
          h[:data][:object][:currency] = "usd"
        end
      end

      it "does not open an intent" do
        result = webhook_service.call

        expect(result).to be_success
        expect(Invoices::Payments::CreateJob).not_to have_received(:perform_later)
      end
    end

    context "when the invoice is already paid" do
      let(:invoice) do
        create(:invoice, organization:, customer:, currency: "EUR", status: :finalized, payment_status: :succeeded)
      end

      it "does not open an intent" do
        result = webhook_service.call

        expect(result).to be_success
        expect(Invoices::Payments::CreateJob).not_to have_received(:perform_later)
      end
    end

    context "when the stripe customer is unknown" do
      let(:event_json) do
        get_stripe_fixtures("webhooks/customer_cash_balance_transaction_created.json") do |h|
          h[:data][:object][:customer] = "cus_unknown"
        end
      end

      it "does not open an intent" do
        result = webhook_service.call

        expect(result).to be_success
        expect(Invoices::Payments::CreateJob).not_to have_received(:perform_later)
      end
    end
  end
end
