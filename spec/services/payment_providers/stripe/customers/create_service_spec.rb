# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Stripe::Customers::CreateService, type: :service do
  let(:create_service) { described_class.new(customer:, payment_provider_id:, params:, async:) }

  let(:customer) { create(:customer) }
  let(:stripe_provider) { create(:stripe_provider, organization: customer.organization) }
  let(:payment_provider_id) { stripe_provider.id }
  let(:params) { {provider_customer_id: "id", sync_with_provider: true, provider_payment_methods:} }
  let(:async) { true }

  let(:provider_payment_methods) { %w[card] }

  describe ".call" do
    it "creates a payment_provider_customer" do
      result = create_service.call

      expect(result).to be_success
      expect(result.provider_customer).to be_present
      expect(result.provider_customer.provider_customer_id).to eq("id")
    end

    context "when payment provider is stripe" do
      context "when provider customer is persisted" do
        before do
          create(
            :stripe_customer,
            customer:,
            payment_provider: stripe_provider,
            provider_payment_methods: %w[sepa_debit]
          )
        end

        context "when provider payment methods are present" do
          let(:provider_payment_methods) { %w[card sepa_debit] }

          it "updates payment methods" do
            result = create_service.call

            expect(result.provider_customer.provider_payment_methods).to eq(provider_payment_methods)
          end
        end

        context "when provider payment methods are not present" do
          let(:provider_payment_methods) { nil }

          it "does not update payment methods" do
            result = create_service.call

            expect(result.provider_customer.provider_payment_methods).to eq(%w[sepa_debit])
          end
        end
      end

      context "when provider customer is not persisted" do
        context "when provider payment methods are present" do
          let(:provider_payment_methods) { %w[card sepa_debit] }

          it "saves payment methods" do
            result = create_service.call

            expect(result.provider_customer.provider_payment_methods).to eq(provider_payment_methods)
          end
        end

        context "when provider payment methods are not present" do
          let(:provider_payment_methods) { nil }

          it "saves default payment method" do
            result = create_service.call

            expect(result.provider_customer.provider_payment_methods).to eq(%w[card])
          end
        end
      end
    end

    context "when no provider customer id and should create on service" do
      let(:params) do
        {provider_customer_id: nil, sync_with_provider: true, provider_payment_methods: %w[card]}
      end

      it "enqueues a job to create the customer on the provider" do
        expect { create_service.call }.to have_enqueued_job(PaymentProviderCustomers::StripeCreateJob)
      end
    end

    context "when removing the provider customer id and should create on service" do
      let(:params) do
        {provider_customer_id: nil, sync_with_provider: true}
      end

      let(:stripe_customer) do
        create(
          :stripe_customer,
          customer:,
          payment_provider: stripe_provider
        )
      end

      before { stripe_customer }

      it "updates the provider customer" do
        expect do
          result = create_service.call

          aggregate_failures do
            expect(result).to be_success

            expect(result.provider_customer.provider_customer_id).to be_nil
          end
        end.not_to have_enqueued_job(PaymentProviderCustomers::StripeCreateJob)
      end
    end

    context "when provider customer id is set" do
      let(:params) do
        {provider_customer_id: "id", sync_with_provider:, provider_payment_methods: %w[card]}
      end

      before do
        allow(create_service).to receive(:generate_checkout_url).and_return(true)
        allow(create_service).to receive(:create_customer_on_provider_service).and_return(true)
      end

      context "when sync with provider is blank" do
        let(:sync_with_provider) { nil }

        let(:provider) { create(:stripe_provider, organization: customer.organization) }

        context "when provider customer exists" do
          before do
            create(:stripe_customer, customer:, payment_provider_id: provider.id)
          end

          it "generates checkout url" do
            create_service.call
            expect(create_service).to have_received(:generate_checkout_url)
          end

          it "does not create customer" do
            create_service.call
            expect(create_service).not_to have_received(:create_customer_on_provider_service)
          end
        end

        context "when provider customer does not exist" do
          it "does not generate checkout url" do
            create_service.call
            expect(create_service).not_to have_received(:generate_checkout_url)
          end

          it "does not create customer" do
            create_service.call
            expect(create_service).not_to have_received(:create_customer_on_provider_service)
          end
        end
      end

      context "when sync with provider is true" do
        let(:sync_with_provider) { true }
        let(:provider) { create(:stripe_provider, organization: customer.organization) }

        it "does not generate checkout url" do
          create_service.call
          expect(create_service).not_to have_received(:generate_checkout_url)
        end

        it "does not enqueue a job to create the customer on the provider" do
          expect { create_service.call }.not_to enqueue_job(PaymentProviderCustomers::StripeCreateJob)
        end
      end
    end
  end
end
