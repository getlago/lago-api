# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::PaystackService do
  subject(:paystack_service) { described_class.new }

  let(:organization) { create(:organization) }
  let(:code) { "paystack_1" }
  let(:name) { "Paystack 1" }
  let(:secret_key) { "sk_test_#{SecureRandom.hex(24)}" }
  let(:success_redirect_url) { Faker::Internet.url }

  describe "#create_or_update" do
    it "creates a paystack provider" do
      expect do
        paystack_service.create_or_update(
          organization:,
          code:,
          name:,
          secret_key:,
          success_redirect_url:
        )
      end.to change(PaymentProviders::PaystackProvider, :count).by(1)
    end

    context "when the provider already exists" do
      let(:payment_provider) { create(:paystack_provider, organization:, code:, name: "Old name") }

      before { payment_provider }

      it "updates the provider" do
        result = paystack_service.create_or_update(
          id: payment_provider.id,
          organization:,
          code:,
          name:,
          secret_key:,
          success_redirect_url:
        )

        expect(result).to be_success
        expect(result.paystack_provider).to have_attributes(
          id: payment_provider.id,
          code:,
          name:,
          secret_key:,
          success_redirect_url:
        )
      end
    end

    context "when code was changed" do
      let(:new_code) { "paystack_updated" }
      let(:payment_provider) { create(:paystack_provider, organization:, code:) }
      let(:customer) { create(:customer, organization:, payment_provider: "paystack", payment_provider_code: code) }
      let(:paystack_customer) { create(:paystack_customer, payment_provider:, customer:) }

      before { paystack_customer }

      it "updates provider codes of the linked customers" do
        result = paystack_service.create_or_update(
          id: payment_provider.id,
          organization:,
          code: new_code,
          name:,
          secret_key:
        )

        expect(result).to be_success
        expect(customer.reload.payment_provider_code).to eq(new_code)
      end
    end

    context "with invalid attributes" do
      let(:secret_key) { nil }

      it "returns a validation failure" do
        result = paystack_service.create_or_update(
          organization:,
          code:,
          name:,
          secret_key:
        )

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
      end
    end
  end
end
