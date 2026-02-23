# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::Payments::CancelService do
  subject(:result) { described_class.call(invoice:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, :activating, customer:) }
  let(:invoice) { create(:invoice, customer:, organization:) }

  before do
    create(:invoice_subscription, invoice:, subscription:)
  end

  context "when there is no pending payment" do
    it "returns a successful result" do
      expect(result).to be_success
    end
  end

  context "when there is a pending payment with a stripe provider" do
    let(:stripe_provider) { create(:stripe_provider, organization:) }
    let(:payment) do
      create(
        :payment,
        payable: invoice,
        payment_provider: stripe_provider,
        provider_payment_id: "pi_123",
        payable_payment_status: "pending"
      )
    end

    before do
      payment
      allow(::Stripe::PaymentIntent).to receive(:cancel).and_return(true)
    end

    it "cancels the payment intent on stripe" do
      result

      expect(::Stripe::PaymentIntent).to have_received(:cancel).with(
        "pi_123",
        {},
        {api_key: stripe_provider.secret_key}
      )
    end

    it "returns a successful result" do
      expect(result).to be_success
    end
  end

  context "when there is a pending payment with an adyen provider" do
    let(:adyen_provider) { create(:adyen_provider, organization:) }
    let(:payment) do
      create(
        :payment,
        payable: invoice,
        payment_provider: adyen_provider,
        provider_payment_id: "psp_123",
        payable_payment_status: "pending"
      )
    end
    let(:adyen_client) { instance_double(Adyen::Client) }
    let(:checkout) { instance_double(Adyen::Checkout) }
    let(:modifications_api) { instance_double(Adyen::ModificationsApi) }

    before do
      payment
      allow(::Adyen::Client).to receive(:new).and_return(adyen_client)
      allow(adyen_client).to receive(:checkout).and_return(checkout)
      allow(checkout).to receive(:modifications_api).and_return(modifications_api)
      allow(modifications_api).to receive(:cancel_authorised_payment_by_psp_reference).and_return(true)
    end

    it "cancels the payment on adyen" do
      result

      expect(modifications_api).to have_received(:cancel_authorised_payment_by_psp_reference).with(
        hash_including(merchantAccount: adyen_provider.merchant_account),
        "psp_123"
      )
    end

    it "returns a successful result" do
      expect(result).to be_success
    end
  end

  context "when there is a pending payment with a gocardless provider" do
    let(:gocardless_provider) { create(:gocardless_provider, organization:) }
    let(:payment) do
      create(
        :payment,
        payable: invoice,
        payment_provider: gocardless_provider,
        provider_payment_id: "gc_pay_123",
        payable_payment_status: "pending"
      )
    end
    let(:gocardless_client) { instance_double(GoCardlessPro::Client) }
    let(:payments_service) { instance_double(GoCardlessPro::Services::PaymentsService) }

    before do
      payment
      allow(GoCardlessPro::Client).to receive(:new).and_return(gocardless_client)
      allow(gocardless_client).to receive(:payments).and_return(payments_service)
      allow(payments_service).to receive(:cancel).and_return(true)
    end

    it "cancels the payment on gocardless" do
      result

      expect(payments_service).to have_received(:cancel).with("gc_pay_123")
    end

    it "returns a successful result" do
      expect(result).to be_success
    end
  end

  context "when payment cancellation fails" do
    let(:stripe_provider) { create(:stripe_provider, organization:) }
    let(:payment) do
      create(
        :payment,
        payable: invoice,
        payment_provider: stripe_provider,
        provider_payment_id: "pi_123",
        payable_payment_status: "pending"
      )
    end

    before do
      payment
      allow(::Stripe::PaymentIntent).to receive(:cancel).and_raise(Stripe::StripeError.new("already captured"))
      allow(Rails.logger).to receive(:warn)
    end

    it "logs a warning and returns a successful result" do
      expect(result).to be_success
      expect(Rails.logger).to have_received(:warn).with(/Payment cancellation failed/)
    end
  end

  context "when payment has no provider" do
    let(:payment) do
      create(
        :payment,
        payable: invoice,
        payment_provider: nil,
        payable_payment_status: "pending"
      )
    end

    before { payment }

    it "returns a successful result" do
      expect(result).to be_success
    end
  end
end
