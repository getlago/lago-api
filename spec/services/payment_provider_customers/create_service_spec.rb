# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviderCustomers::CreateService, type: :service do
  let(:create_service) { described_class.new(customer) }

  let(:customer) { create(:customer) }
  let(:stripe_provider) { create(:stripe_provider, organization: customer.organization) }

  let(:create_params) do
    {provider_customer_id: "id", sync_with_provider: true, provider_payment_methods:}
  end

  let(:provider_payment_methods) { %w[card] }

  describe ".create_or_update" do
    it "creates a payment_provider_customer" do
      result = create_service.create_or_update(
        customer_class: PaymentProviderCustomers::StripeCustomer,
        payment_provider_id: stripe_provider.id,
        params: create_params
      )

      expect(result).to be_success
      expect(result.provider_customer).to be_present
      expect(result.provider_customer.provider_customer_id).to eq("id")
    end

    context "when payment provider is stripe" do
      let(:service_call) do
        create_service.create_or_update(
          customer_class: PaymentProviderCustomers::StripeCustomer,
          payment_provider_id: stripe_provider.id,
          params: create_params
        )
      end

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
            result = service_call

            expect(result.provider_customer.provider_payment_methods).to eq(provider_payment_methods)
          end
        end

        context "when provider payment methods are not present" do
          let(:provider_payment_methods) { nil }

          it "does not update payment methods" do
            result = service_call

            expect(result.provider_customer.provider_payment_methods).to eq(%w[sepa_debit])
          end
        end
      end

      context "when provider customer is not persisted" do
        context "when provider payment methods are present" do
          let(:provider_payment_methods) { %w[card sepa_debit] }

          it "saves payment methods" do
            result = service_call

            expect(result.provider_customer.provider_payment_methods).to eq(provider_payment_methods)
          end
        end

        context "when provider payment methods are not present" do
          let(:provider_payment_methods) { nil }

          it "saves default payment method" do
            result = service_call

            expect(result.provider_customer.provider_payment_methods).to eq(%w[card])
          end
        end
      end
    end

    context "when no provider customer id and should create on service" do
      let(:create_params) do
        {provider_customer_id: nil, sync_with_provider: true, provider_payment_methods: %w[card]}
      end

      it "enqueues a job to create the customer on the provider" do
        expect do
          create_service.create_or_update(
            customer_class: PaymentProviderCustomers::StripeCustomer,
            payment_provider_id: stripe_provider.id,
            params: create_params
          )
        end.to have_enqueued_job(PaymentProviderCustomers::StripeCreateJob)
      end
    end

    context "when no gocardless provider customer id and should create on service" do
      let(:create_params) do
        {provider_customer_id: nil, sync_with_provider: true}
      end

      let(:gocardless_provider) do
        create(
          :gocardless_provider,
          organization: customer.organization
        )
      end

      it "enqueues a job to create the customer on the provider" do
        expect do
          create_service.create_or_update(
            customer_class: PaymentProviderCustomers::GocardlessCustomer,
            payment_provider_id: gocardless_provider.id,
            params: create_params
          )
        end.to have_enqueued_job(PaymentProviderCustomers::GocardlessCreateJob)
      end
    end

    context "when removing the provider customer id and should create on service" do
      let(:create_params) do
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
          result = create_service.create_or_update(
            customer_class: PaymentProviderCustomers::StripeCustomer,
            payment_provider_id: stripe_provider.id,
            params: create_params
          )

          aggregate_failures do
            expect(result).to be_success

            expect(result.provider_customer.provider_customer_id).to be_nil
          end
        end.not_to have_enqueued_job(PaymentProviderCustomers::StripeCreateJob)
      end
    end

    context "when provider customer id is set" do
      subject(:create_or_update) do
        create_service.create_or_update(
          customer_class:,
          payment_provider_id: provider.id,
          params: create_params
        )
      end

      let(:create_params) do
        {provider_customer_id: "id", sync_with_provider:, provider_payment_methods: %w[card]}
      end

      before do
        allow(create_service).to receive(:generate_checkout_url).and_return(true)
        allow(create_service).to receive(:create_customer_on_provider_service).and_return(true)
      end

      context "when sync with provider is blank" do
        let(:sync_with_provider) { nil }

        context "when customer type is adyen" do
          let(:customer_class) { PaymentProviderCustomers::AdyenCustomer }
          let(:provider) { create(:adyen_provider, organization: customer.organization) }

          context "when provider customer exists" do
            before do
              create(:adyen_customer, customer:, payment_provider_id: provider.id)
            end

            it "generates checkout url" do
              create_or_update
              expect(create_service).to have_received(:generate_checkout_url)
            end

            it "does not create customer" do
              create_or_update
              expect(create_service).not_to have_received(:create_customer_on_provider_service)
            end
          end

          context "when provider customer does not exist" do
            it "does not generate checkout url" do
              create_or_update
              expect(create_service).not_to have_received(:generate_checkout_url)
            end

            it "does not create customer" do
              create_or_update
              expect(create_service).not_to have_received(:create_customer_on_provider_service)
            end
          end
        end

        context "when customer type is gocardless" do
          let(:customer_class) { PaymentProviderCustomers::GocardlessCustomer }
          let(:provider) { create(:gocardless_provider, organization: customer.organization) }

          context "when provider customer exists" do
            before do
              create(:gocardless_customer, customer:, payment_provider_id: provider.id)
            end

            it "generates checkout url" do
              create_or_update
              expect(create_service).to have_received(:generate_checkout_url)
            end

            it "does not create customer" do
              create_or_update
              expect(create_service).not_to have_received(:create_customer_on_provider_service)
            end
          end

          context "when provider customer does not exist" do
            it "does not generate checkout url" do
              create_or_update
              expect(create_service).not_to have_received(:generate_checkout_url)
            end

            it "does not create customer" do
              create_or_update
              expect(create_service).not_to have_received(:create_customer_on_provider_service)
            end
          end
        end

        context "when customer type is stripe" do
          let(:customer_class) { PaymentProviderCustomers::StripeCustomer }
          let(:provider) { create(:stripe_provider, organization: customer.organization) }

          context "when provider customer exists" do
            before do
              create(:stripe_customer, customer:, payment_provider_id: provider.id)
            end

            it "generates checkout url" do
              create_or_update
              expect(create_service).to have_received(:generate_checkout_url)
            end

            it "does not create customer" do
              create_or_update
              expect(create_service).not_to have_received(:create_customer_on_provider_service)
            end
          end

          context "when provider customer does not exist" do
            it "does not generate checkout url" do
              create_or_update
              expect(create_service).not_to have_received(:generate_checkout_url)
            end

            it "does not create customer" do
              create_or_update
              expect(create_service).not_to have_received(:create_customer_on_provider_service)
            end
          end
        end
      end

      context "when sync with provider is true" do
        let(:sync_with_provider) { true }

        context "when customer type is stripe" do
          let(:customer_class) { PaymentProviderCustomers::StripeCustomer }
          let(:provider) { create(:stripe_provider, organization: customer.organization) }

          it "does not generate checkout url" do
            create_or_update
            expect(create_service).not_to have_received(:generate_checkout_url)
          end

          it "does not enqueue a job to create the customer on the provider" do
            expect { create_or_update }.not_to enqueue_job(PaymentProviderCustomers::StripeCreateJob)
          end
        end

        context "when customer type is adyen" do
          let(:customer_class) { PaymentProviderCustomers::AdyenCustomer }
          let(:provider) { create(:adyen_provider, organization: customer.organization) }

          it "does not generate checkout url" do
            create_or_update
            expect(create_service).not_to have_received(:generate_checkout_url)
          end

          it "does not enqueue a job to create the customer on the provider" do
            expect { create_or_update }.not_to enqueue_job(PaymentProviderCustomers::AdyenCreateJob)
          end
        end

        context "when customer type is gocardless" do
          let(:customer_class) { PaymentProviderCustomers::GocardlessCustomer }
          let(:provider) { create(:gocardless_provider, organization: customer.organization) }

          it "does not generate checkout url" do
            create_or_update
            expect(create_service).not_to have_received(:generate_checkout_url)
          end

          it "does not enqueue a job to create the customer on the provider" do
            expect { create_or_update }.not_to enqueue_job(PaymentProviderCustomers::GocardlessCreateJob)
          end
        end
      end
    end
  end
end
