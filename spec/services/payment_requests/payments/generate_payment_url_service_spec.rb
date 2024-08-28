# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentRequests::Payments::GeneratePaymentUrlService, type: :service do
  subject(:generate_payment_url_service) { described_class.new(payable: payment_request) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, payment_provider:, payment_provider_code: code) }
  let(:payment_request) { create(:payment_request, customer:) }
  let(:payment_provider) { "stripe" }
  let(:code) { "stripe_1" }

  describe ".call" do
    let(:stripe_provider) { create(:stripe_provider, organization:, code:) }

    before do
      create(
        :stripe_customer,
        customer_id: customer.id,
        payment_provider: stripe_provider
      )

      allow(Stripe::Checkout::Session).to receive(:create)
        .and_return({"url" => "https://example55.com"})
    end

    it "returns the generated payment url" do
      result = generate_payment_url_service.call

      expect(result.payment_url).to eq("https://example55.com")
    end

    context "when payment provider is blank" do
      let(:payment_provider) { nil }

      it "returns an error", :aggregate_failures do
        result = generate_payment_url_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:base]).to eq(["no_linked_payment_provider"])
      end
    end

    context "when payment provider is gocardless" do
      let(:payment_provider) { "gocardless" }

      it "returns an error", :aggregate_failures do
        result = generate_payment_url_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:base]).to eq(["invalid_payment_provider"])
      end
    end

    context "when payment request's payment status is invalid" do
      before { payment_request.payment_succeeded! }

      it "returns an error", :aggregate_failures do
        result = generate_payment_url_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:base]).to eq(["invalid_payment_status"])
      end
    end
  end
end
