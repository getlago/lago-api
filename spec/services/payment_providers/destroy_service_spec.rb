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

    context "with attached payment provider customers" do
      let(:customer) { create(:customer, organization:) }
      let(:payment_provider_customer) { create(:stripe_customer, customer:, organization:, payment_provider:) }

      before { payment_provider_customer }

      it "soft deletes the payment provider customers" do
        expect { destroy_service.call }
          .to change { payment_provider_customer.reload.discarded? }.from(false).to(true)
      end

      it "detaches the payment provider customers from the payment provider" do
        destroy_service.call

        expect(payment_provider_customer.reload.payment_provider_id).to be_nil
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
