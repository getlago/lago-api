# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::UpdatePaymentMethodDataService, type: :service do
  subject(:service) { described_class.new(payment:, provider_payment_method_id:) }

  let(:provider_payment_method_id) { "pm_1R2DFsQ8iJWBZFaMw3LLbR0r" }

  describe "#call" do
    context "with Stripe" do
      let(:payment) { create(:payment, payment_provider: create(:stripe_provider)) }

      it "updates the payment method data" do
        stub_request(:get, %r{/v1/payment_methods/pm_1R2DFsQ8iJWBZFaMw3LLbR0r$}).and_return(
          status: 200, body: File.read(Rails.root.join("spec/fixtures/stripe/retrieve_payment_method.json"))
        )

        result = service.call

        expect(result.payment.provider_payment_method_id).to eq "pm_1R2DFsQ8iJWBZFaMw3LLbR0r"
        expect(result.payment.provider_payment_method_data).to eq({
          "type" => "card",
          "brand" => "visa",
          "last4" => "4242"
        })
      end

      context "when the payment method id is already set" do
        it "does not call stripe" do
          payment.update!(
            provider_payment_method_id: provider_payment_method_id,
            provider_payment_method_data: {existing: "data"}
          )
          result = service.call
          expect(result.payment.provider_payment_method_id).to eq provider_payment_method_id
          expect(result.payment.provider_payment_method_data).to eq({"existing" => "data"})
        end
      end

      context "with force argument" do
        it "does not call stripe" do
          stub_request(:get, %r{/v1/payment_methods/pm_1R2DFsQ8iJWBZFaMw3LLbR0r$}).and_return(
            status: 200, body: File.read(Rails.root.join("spec/fixtures/stripe/retrieve_payment_method.json"))
          )
          payment.update!(
            provider_payment_method_id: provider_payment_method_id,
            provider_payment_method_data: {existing: "data"}
          )

          result = described_class.new(payment:, provider_payment_method_id:, force: true).call

          expect(result.payment.provider_payment_method_id).to eq "pm_1R2DFsQ8iJWBZFaMw3LLbR0r"
          expect(result.payment.provider_payment_method_data).to eq({
            "type" => "card",
            "brand" => "visa",
            "last4" => "4242"
          })
        end
      end
    end

    context "with any other provider" do
      let(:payment) { create(:payment, payment_provider: create(:gocardless_provider)) }

      it do
        expect { service.call }.to raise_error(NotImplementedError)
      end
    end
  end
end
