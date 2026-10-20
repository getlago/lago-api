# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::SetPaymentMethodAndCreateReceiptJob do
  before_all do
    create_default(:organization)
    create_default(:invoice)
  end

  let(:payment) { create(:payment) }
  let(:provider_payment_method_id) { "pm_001" }

  before do
    allow(Payments::SetPaymentMethodDataService)
      .to receive(:call!).with(payment:, provider_payment_method_id:).and_return(Payments::SetPaymentMethodDataService::Result.new)
  end

  it "calls the service" do
    described_class.perform_now(payment:, provider_payment_method_id:)

    expect(Payments::SetPaymentMethodDataService).to have_received(:call!)
  end

  context "with customer payment_method" do
    let(:customer) { payment.customer }
    let(:payment_method) do
      create(
        :payment_method,
        customer:,
        payment_provider_customer: payment.payment_provider_customer,
        provider_method_id: provider_payment_method_id
      )
    end

    before { payment_method }

    it "attachs the payment method to the payment" do
      described_class.perform_now(payment:, provider_payment_method_id:)
      expect(payment.payment_method_id).to eq(payment_method.id)
    end
  end

  context "without customer payment_method" do
    let(:customer) { create(:customer) }
    let(:organization) { customer.organization }
    let(:invoice) { create(:invoice, customer:, organization:) }
    let(:stripe_provider) { create(:stripe_provider, organization:) }
    let(:stripe_customer) do
      create(:stripe_customer, customer:, payment_provider: stripe_provider, provider_payment_methods: %w[card])
    end
    let(:payment) do
      create(
        :payment,
        payable: invoice,
        customer:,
        organization:,
        payment_provider: stripe_provider,
        payment_provider_customer: stripe_customer
      )
    end

    before do
      allow(Payments::SetPaymentMethodDataService).to receive(:call!).and_call_original
      stub_request(:get, %r{/v1/payment_methods/#{provider_payment_method_id}}).and_return(
        status: 200,
        body: get_stripe_fixtures("retrieve_payment_method_response.json")
      )
    end

    it "creates and attaches the payment method" do
      expect { described_class.perform_now(payment:, provider_payment_method_id:) }
        .to change(PaymentMethod, :count).by(1)

      payment_method = payment.reload.payment_method
      expect(payment_method.customer).to eq(customer)
      expect(payment_method.payment_provider_customer).to eq(stripe_customer)
      expect(payment_method.provider_method_id).to eq(provider_payment_method_id)
      expect(payment_method.details).to include("type" => "card", "brand" => "visa", "last4" => "4242")
    end
  end

  context "when payment method creation raises BaseService::LockAcquisitionFailure" do
    before do
      allow(PaymentMethods::FindOrCreateFromProviderService)
        .to receive(:call!)
        .and_raise(BaseService::LockAcquisitionFailure.new(nil, code: "lock_acquisition_failed", error_message: "Failed to acquire lock"))
    end

    it "retries the job instead of dying" do
      expect do
        described_class.perform_now(payment:, provider_payment_method_id:)
      end.to have_enqueued_job(described_class)
    end
  end

  context "when payment method creation raises ActiveRecord::Deadlocked" do
    before do
      allow(PaymentMethods::FindOrCreateFromProviderService)
        .to receive(:call!)
        .and_raise(ActiveRecord::Deadlocked)
    end

    it "retries the job instead of dying" do
      expect do
        described_class.perform_now(payment:, provider_payment_method_id:)
      end.to have_enqueued_job(described_class)
    end
  end
end
