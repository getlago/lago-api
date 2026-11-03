# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviderCustomers::UpdateService do
  subject(:result) { described_class.call(customer) }

  let(:customer) { create(:customer, payment_provider: provider_name.downcase) }
  let(:payment_provider) { create(:stripe_provider, organization: customer.organization) }
  let(:provider_name) { "Stripe" }
  let(:provider_service_class) { "PaymentProviderCustomers::#{provider_name}Service".constantize }
  let!(:provider_customer) { create(:"#{provider_name.downcase}_customer", customer:) }

  before do
    allow(provider_service_class).to receive(:call).and_return(provider_service_class::RESULTS.fetch(:update).new)
    allow(Stripe::Customer).to receive(:update).and_return(true)
  end

  describe "#call" do
    before { payment_provider }

    it "updates the provider customer" do
      expect(result).to be_success
      expect(provider_service_class).to have_received(:call).with(:update, provider_customer)
    end

    context "when the customer has another connection that is not the default" do
      before do
        create(:gocardless_customer, customer:)
        allow(PaymentProviderCustomers::GocardlessService).to receive(:call)
      end

      it "updates the default provider customer" do
        expect(result).to be_success
        expect(provider_service_class).to have_received(:call).with(:update, provider_customer)
        expect(PaymentProviderCustomers::GocardlessService).not_to have_received(:call)
      end
    end

    context "when the customer has no default payment provider" do
      let(:customer) { create(:customer, payment_provider: nil) }

      it "succeeds without calling the provider" do
        expect(result).to be_success
        expect(provider_service_class).not_to have_received(:call)
        expect(Stripe::Customer).not_to have_received(:update)
      end
    end

    context "when the default provider connection is discarded" do
      before { provider_customer.discard }

      it "succeeds without calling the provider" do
        expect(result).to be_success
        expect(provider_service_class).not_to have_received(:call)
        expect(Stripe::Customer).not_to have_received(:update)
      end
    end
  end
end
