# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::CreatePaymentFactory, type: :service do
  subject(:new_instance) { described_class.new_instance(provider:, invoice:, provider_customer:) }

  let(:provider) { "stripe" }
  let(:invoice) { create(:invoice) }
  let(:provider_customer) { create(:stripe_customer) }

  describe ".new_instance" do
    it "creates an instance of the stripe service" do
      expect(new_instance).to be_instance_of(PaymentProviders::Stripe::Payments::CreateService)
    end

    context "when provider is adyen" do
      let(:provider) { "adyen" }
      let(:provider_customer) { create(:adyen_customer) }

      it "creates an instance of the adyen service" do
        expect(new_instance).to be_instance_of(PaymentProviders::Adyen::Payments::CreateService)
      end
    end

    context "when provider is gocardless" do
      let(:provider) { "gocardless" }
      let(:provider_customer) { create(:gocardless_customer) }

      it "creates an instance of the gocardless service" do
        expect(new_instance).to be_instance_of(PaymentProviders::Gocardless::Payments::CreateService)
      end
    end
  end
end
