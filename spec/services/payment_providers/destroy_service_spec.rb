# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::DestroyService do
  subject(:destroy_service) { described_class.new(payment_provider) }

  include_context "with mocked security logger"

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:payment_provider) { create(:stripe_provider, organization:) }

  describe ".destroy" do
    before { payment_provider }

    it "destroys the payment_provider" do
      expect { destroy_service.call }
        .to change(PaymentProviders::BaseProvider, :count).by(-1)
    end

    it_behaves_like "produces a security log", "integration.deleted" do
      before { destroy_service.call }
    end

    context "with provider customers" do
      let(:customer) { create(:customer, organization:) }
      let(:provider_customer) { create(:stripe_customer, customer:, organization:, payment_provider:) }

      before { provider_customer }

      it "soft-deletes the provider customers" do
        destroy_service.call

        expect(provider_customer.reload).to be_discarded
      end

      it "removes the provider customers from the default scope" do
        destroy_service.call

        expect(PaymentProviderCustomers::BaseCustomer.find_by(id: provider_customer.id)).to be_nil
      end

      it "nullifies the payment provider on the customer" do
        destroy_service.call

        expect(customer.reload).to have_attributes(payment_provider: nil, payment_provider_code: nil)
      end

      it "allows a single live provider customer per customer/type after reconnect" do
        destroy_service.call

        new_provider = create(:stripe_provider, organization:)
        expect { create(:stripe_customer, customer:, organization:, payment_provider: new_provider) }
          .to change { PaymentProviderCustomers::StripeCustomer.where(customer:).count }.from(0).to(1)
      end
    end

    context "when payment provider is not found" do
      let(:payment_provider) { nil }

      it "returns an error" do
        result = destroy_service.call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq("payment_provider_not_found")
      end
    end
  end
end
