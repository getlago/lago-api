# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::CreatePaymentFactory, type: :service do
  subject(:new_instance) { described_class.new_instance(provider:, invoice:) }

  let(:provider) { "stripe" }
  let(:invoice) { create(:invoice) }

  describe ".new_instance" do
    it "creates an instance of the stripe service" do
      expect(new_instance).to be_instance_of(Invoices::Payments::StripeService)
    end

    context "when provider is adyen" do
      let(:provider) { "adyen" }

      it "creates an instance of the adyen service" do
        expect(new_instance).to be_instance_of(Invoices::Payments::AdyenService)
      end
    end

    context "when provider is gocardless" do
      let(:provider) { "gocardless" }

      it "creates an instance of the gocardless service" do
        expect(new_instance).to be_instance_of(Invoices::Payments::GocardlessService)
      end
    end
  end
end
