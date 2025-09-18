# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Stripe::Webhooks::SetupIntentSucceededService do
  subject(:webhook_service) { described_class.new(organization_id: organization.id, event:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }

  let(:event) { Stripe::Event.construct_from(JSON.parse(event_json)) }
  let(:provider_customer_id) { event.data.object.customer }
  let(:payment_method_id) { event.data.object.payment_method }

  let(:stripe_provider) { create(:stripe_provider, organization:) }
  let(:stripe_customer) do
    create(:stripe_customer, payment_provider: stripe_provider, customer:, provider_customer_id:)
  end

  before do
    stripe_customer

    stub_request(:get, "https://api.stripe.com/v1/payment_methods/#{payment_method_id}")
      .to_return(status: 200, body: payment_method, headers: {})
  end

  ["2020-08-27", "2025-04-30.basil"].each do |version|
    let(:payment_method) { get_stripe_fixtures("retrieve_payment_method_response.json", version:) }

    describe "#call" do
      context "when stripe customer id is nil" do
        let(:event_json) { get_stripe_fixtures("webhooks/setup_intent_succeeded.json", version:) }

        it "returns an empty result" do
          result = webhook_service.call

          expect(result).to be_success
          expect(result.payment_method).to be_nil
        end
      end

      context "when payment method has no customer" do
        let(:event_json) do
          get_stripe_fixtures("webhooks/setup_intent_succeeded.json", version:) do |h|
            h[:data][:object][:customer] = "cus_123" if h[:data][:object][:customer].nil?
          end
        end
        let(:payment_method) do
          get_stripe_fixtures("retrieve_payment_method_response.json", version:) do |h|
            h[:customer] = nil
          end
        end

        it "returns an empty result" do
          result = webhook_service.call

          expect(result).to be_success
          expect(result.payment_method).to be_nil
        end
      end

      context "when provider customer id is set" do
        let(:event_json) do
          get_stripe_fixtures("webhooks/setup_intent_succeeded.json", version:) do |h|
            h[:data][:object][:customer] = "cus_123" if h[:data][:object][:customer].nil?
          end
        end

        it "updates provider default payment method" do
          allow(Stripe::Customer).to receive(:update).and_return(true)

          result = webhook_service.call

          expect(result).to be_success
          expect(result.payment_method_id).to start_with("pm_")
          expect(result.payment_method_id).to eq(payment_method_id)
          expect(result.stripe_customer).to eq(stripe_customer)
          expect(result.stripe_customer.payment_method_id).to eq(payment_method_id)

          expect(Stripe::Customer).to have_received(:update).with(
            provider_customer_id,
            {invoice_settings: {default_payment_method: payment_method_id}},
            {api_key: stripe_provider.secret_key}
          )
        end
      end

      context "when stripe customer is not found" do
        let(:event_json) do
          get_stripe_fixtures("webhooks/setup_intent_succeeded.json", version:) do |h|
            h[:data][:object][:customer] = "cus_666" if h[:data][:object][:customer].nil?
            h[:data][:object][:metadata] = metadata
          end
        end
        let(:stripe_customer) do
          create(:stripe_customer, payment_provider: stripe_provider, customer:, provider_customer_id: "cus_123")
        end

        context "when metadata is empty" do
          let(:metadata) { {} }

          it "returns an empty result" do
            result = webhook_service.call

            expect(result).to be_success
            expect(result.payment_method).to be_nil
          end
        end

        context "when customer in metadata exists in another organization" do
          let(:customer) { create(:customer, organization: create(:organization)) }
          let(:metadata) { {lago_customer_id: customer.id} }

          it "returns an empty result" do
            result = webhook_service.call

            expect(result).to be_success
            expect(result.payment_method).to be_nil
          end
        end

        context "when customer in metadata exists in this org" do
          let(:metadata) { {lago_customer_id: customer.id} }

          context "when is linked to another stripe customer" do
            it "returns an empty result" do
              result = webhook_service.call

              expect(result).to be_success
              expect(result.payment_method).to be_nil
            end
          end

          context "when is not linked to another stripe customer" do
            let(:stripe_customer) { nil }

            it "returns a not found error" do
              result = webhook_service.call

              expect(result).not_to be_success
              expect(result.error).to be_a(BaseService::NotFoundFailure)
              expect(result.error.message).to eq("stripe_customer_not_found")
            end
          end
        end
      end
    end
  end
end
