# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::CreateCustomerFactory, type: :service do
  subject(:new_instance) { described_class.new_instance(provider:, customer:, payment_provider_id:, params:, async:) }

  let(:customer) { create(:customer) }
  let(:payment_provider_id) { create(:stripe_provider, organization: customer.organization).id }
  let(:params) { {provider_customer_id: "id", sync_with_provider: true} }
  let(:async) { true }

  let(:provider) { "stripe" }

  describe ".new_instance" do
    it "creates an instance of the stripe service" do
      expect(new_instance).to be_instance_of(PaymentProviders::Stripe::Customers::CreateService)
    end

    context "when provider is adyen" do
      let(:provider) { "adyen" }
      let(:payment_provider_id) { create(:adyen_provider, organization: customer.organization).id }

      it "creates an instance of the adyen service" do
        expect(new_instance).to be_instance_of(PaymentProviders::Adyen::Customers::CreateService)
      end
    end

    context "when provider is gocardless" do
      let(:provider) { "gocardless" }
      let(:payment_provider_id) { create(:gocardless_provider, organization: customer.organization).id }

      it "creates an instance of the gocardless service" do
        expect(new_instance).to be_instance_of(PaymentProviders::Gocardless::Customers::CreateService)
      end
    end
  end
end
