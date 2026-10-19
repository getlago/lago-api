# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::CancelPaymentJob do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:) }
  let(:payment_provider) { create(:stripe_provider, organization:) }
  let(:payment) do
    create(:payment, payable: invoice, payment_provider:, organization:, customer:,
      provider_payment_id: "pi_123", payable_payment_status: :pending)
  end

  before do
    allow(PaymentProviders::CancelPaymentService).to receive(:call!)
  end

  it "forwards the payment to the dispatcher service" do
    described_class.perform_now(payment)

    expect(PaymentProviders::CancelPaymentService).to have_received(:call!).with(payment:)
  end

  describe "retry_on" do
    [
      ::Stripe::RateLimitError.new("Too many requests"),
      ::Stripe::APIConnectionError.new("Connection reset"),
      Invoices::Payments::ConnectionError.new(StandardError.new("Connection failed"))
    ].each do |error|
      context "when the provider raises #{error.class.name}" do
        before { allow(PaymentProviders::CancelPaymentService).to receive(:call!).and_raise(error) }

        it "retries the job" do
          assert_performed_jobs(6, only: [described_class]) do
            expect { described_class.perform_later(payment) }.to raise_error(error.class)
          end
        end
      end
    end
  end
end
