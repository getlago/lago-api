# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Customers::CreateService, type: :service do
  subject(:customers_service) { described_class.new(user) }

  let(:user) { nil }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:external_id) { SecureRandom.uuid }

  describe 'create_from_api' do
    let(:create_args) do
      {
        external_id:,
        name: 'Foo Bar',
        currency: 'EUR',
        tax_identification_number: '123456789',
        billing_configuration: {
          document_locale: 'fr'
        },
        shipping_address: {
          address_line1: 'line1',
          address_line2: 'line2',
          city: 'Paris',
          zipcode: '123456',
          state: 'foobar',
          country: 'FR'
        }
      }
    end

    before do
      allow(SegmentTrackJob).to receive(:perform_later)
      allow(CurrentContext).to receive(:source).and_return('api')
    end

    it 'creates a new customer' do
      result = customers_service.create_from_api(organization:, params: create_args)
      expect(result).to be_success

      aggregate_failures do
        customer = result.customer
        expect(customer.id).to be_present
        expect(customer.organization_id).to eq(organization.id)
        expect(customer.external_id).to eq(create_args[:external_id])
        expect(customer.name).to eq(create_args[:name])
        expect(customer.currency).to eq(create_args[:currency])
        expect(customer.tax_identification_number).to eq(create_args[:tax_identification_number])
        expect(customer.timezone).to be_nil

        billing = create_args[:billing_configuration]
        expect(customer.document_locale).to eq(billing[:document_locale])
        expect(customer.invoice_grace_period).to be_nil

        shipping_address = create_args[:shipping_address]
        expect(customer.shipping_address_line1).to eq(shipping_address[:address_line1])
        expect(customer.shipping_address_line2).to eq(shipping_address[:address_line2])
        expect(customer.shipping_city).to eq(shipping_address[:city])
        expect(customer.shipping_zipcode).to eq(shipping_address[:zipcode])
        expect(customer.shipping_state).to eq(shipping_address[:state])
        expect(customer.shipping_country).to eq(shipping_address[:country])
      end
    end

    it 'creates customer with correctly persisted attributes' do
      result = customers_service.create_from_api(
        organization:,
        params: create_args
      )

      expect(result).to be_success

      customer = Customer.find_by(external_id:)
      billing = create_args[:billing_configuration]

      expect(customer).to have_attributes(
        organization_id: organization.id,
        external_id: create_args[:external_id],
        name: create_args[:name],
        currency: create_args[:currency],
        timezone: nil,
        document_locale: billing[:document_locale],
        invoice_grace_period: nil
      )
    end

    it 'calls SegmentTrackJob' do
      customer = customers_service.create_from_api(
        organization:,
        params: create_args
      ).customer

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: 'customer_created',
        properties: {
          customer_id: customer.id,
          created_at: customer.created_at,
          payment_provider: customer.payment_provider,
          organization_id: customer.organization_id
        }
      )
    end

    context 'with external_id already used by a deleted customer' do
      it 'creates a customer with the same external_id' do
        create(:customer, :deleted, organization:, external_id:)

        aggregate_failures do
          expect { customers_service.create_from_api(organization:, params: create_args) }
            .to change(Customer, :count).by(1)

          customers = organization.customers.with_discarded
          expect(customers.count).to eq(2)
          expect(customers.pluck(:external_id).uniq).to eq([external_id])
        end
      end
    end

    context 'with metadata' do
      let(:create_args) do
        {
          external_id:,
          name: 'Foo Bar',
          currency: 'EUR',
          billing_configuration: {
            document_locale: 'fr'
          },
          metadata: [
            {
              key: 'manager name',
              value: 'John',
              display_in_invoice: true
            },
            {
              key: 'manager address',
              value: 'Test',
              display_in_invoice: false
            }
          ]
        }
      end

      it 'creates customer with metadata' do
        result = customers_service.create_from_api(
          organization:,
          params: create_args
        )

        aggregate_failures do
          expect(result).to be_success

          customer = result.customer
          expect(customer.metadata.count).to eq(2)
        end
      end
    end

    context 'with premium features' do
      around { |test| lago_premium!(&test) }

      let(:create_args) do
        {
          external_id: SecureRandom.uuid,
          name: 'Foo Bar',
          timezone: 'Europe/Paris',
          billing_configuration: {
            invoice_grace_period: 3
          }
        }
      end

      it 'creates a new customer' do
        result = customers_service.create_from_api(
          organization:,
          params: create_args
        )

        expect(result).to be_success

        aggregate_failures do
          customer = result.customer
          expect(customer.timezone).to eq(create_args[:timezone])

          billing = create_args[:billing_configuration]
          expect(customer.invoice_grace_period).to eq(billing[:invoice_grace_period])
        end
      end
    end

    context 'when customer already exists' do
      let(:customer) do
        create(
          :customer,
          organization:,
          external_id:,
          email: 'foo@bar.com'
        )
      end

      before { customer }

      it 'updates the customer' do
        result = customers_service.create_from_api(
          organization:,
          params: create_args
        )

        aggregate_failures do
          expect(result).to be_success
          expect(result.customer).to eq(customer)
          expect(result.customer.name).to eq(create_args[:name])
          expect(result.customer.external_id).to eq(create_args[:external_id])

          # NOTE: It should not erase exsting properties
          expect(result.customer.country).to eq(customer.country)
          expect(result.customer.address_line1).to eq(customer.address_line1)
          expect(result.customer.address_line2).to eq(customer.address_line2)
          expect(result.customer.state).to eq(customer.state)
          expect(result.customer.zipcode).to eq(customer.zipcode)
          expect(result.customer.email).to eq(customer.email)
          expect(result.customer.city).to eq(customer.city)
          expect(result.customer.url).to eq(customer.url)
          expect(result.customer.phone).to eq(customer.phone)
          expect(result.customer.logo_url).to eq(customer.logo_url)
          expect(result.customer.legal_name).to eq(customer.legal_name)
          expect(result.customer.legal_number).to eq(customer.legal_number)
        end
      end

      context 'with provider customer' do
        let(:payment_provider) { create(:stripe_provider, organization:) }
        let(:stripe_customer) { create(:stripe_customer, customer:, payment_provider:) }
        let(:result) { BaseService::Result.new }

        before do
          allow(Stripe::Customer).to receive(:update).and_return(result)
          stripe_customer
          customer.update!(payment_provider: 'stripe')
        end

        it 'updates the customer' do
          result = customers_service.create_from_api(
            organization:,
            params: create_args
          )

          aggregate_failures do
            expect(result).to be_success
            expect(result.customer).to eq(customer)
            expect(result.customer.name).to eq(create_args[:name])
            expect(result.customer.external_id).to eq(create_args[:external_id])
            expect(result.customer.document_locale).to eq(create_args[:billing_configuration][:document_locale])
          end
        end
      end

      context 'with metadata' do
        let(:customer_metadata) { create(:customer_metadata, customer:) }
        let(:another_customer_metadata) { create(:customer_metadata, customer:, key: 'test', value: '1') }
        let(:create_args) do
          {
            external_id:,
            name: 'Foo Bar',
            currency: 'EUR',
            billing_configuration: {
              document_locale: 'fr'
            },
            metadata: [
              {
                id: customer_metadata.id,
                key: 'new key',
                value: 'new value',
                display_in_invoice: true
              },
              {
                key: 'Added key',
                value: 'Added value',
                display_in_invoice: true
              }
            ]
          }
        end

        before do
          customer_metadata
          another_customer_metadata
        end

        it 'updates metadata' do
          result = customers_service.create_from_api(
            organization:,
            params: create_args
          )

          metadata_keys = result.customer.metadata.pluck(:key)
          metadata_ids = result.customer.metadata.pluck(:id)

          expect(result.customer.metadata.count).to eq(2)
          expect(metadata_keys).to eq(['new key', 'Added key'])
          expect(metadata_ids).to include(customer_metadata.id)
          expect(metadata_ids).not_to include(another_customer_metadata.id)
        end

        context 'when more than five metadata objects are provided' do
          let(:create_args) do
            {
              external_id:,
              name: 'Foo Bar',
              currency: 'EUR',
              billing_configuration: {
                document_locale: 'fr'
              },
              metadata: [
                {
                  id: customer_metadata.id,
                  key: 'new key',
                  value: 'new value',
                  display_in_invoice: true
                },
                {
                  key: 'Added key1',
                  value: 'Added value1',
                  display_in_invoice: true
                },
                {
                  key: 'Added key2',
                  value: 'Added value2',
                  display_in_invoice: true
                },
                {
                  key: 'Added key3',
                  value: 'Added value3',
                  display_in_invoice: true
                },
                {
                  key: 'Added key4',
                  value: 'Added value4',
                  display_in_invoice: true
                },
                {
                  key: 'Added key5',
                  value: 'Added value5',
                  display_in_invoice: true
                }
              ]
            }
          end

          it 'fails to create customer with metadata' do
            result = customers_service.create_from_api(
              organization:,
              params: create_args
            )

            aggregate_failures do
              expect(result.error).to be_a(BaseService::ValidationFailure)
              expect(result.error.messages.keys).to include(:metadata)
              expect(result.error.messages[:metadata]).to include('invalid_count')
            end
          end
        end
      end

      context 'with integration customers' do
        let(:create_args) do
          {
            external_id:,
            name: 'Foo Bar',
            currency: 'EUR',
            billing_configuration: {
              document_locale: 'fr'
            },
            integration_customers:
          }
        end

        context 'when there are netusite and anrok customer sent' do
          let(:integration_customers) do
            [
              {
                external_customer_id: '12345',
                integration_type: 'netsuite',
                integration_code: 'code1',
                subsidiary_id: '1',
                sync_with_provider: true
              },
              {
                external_customer_id: '65432',
                integration_type: 'anrok',
                integration_code: 'code3',
                sync_with_provider: true
              }
            ]
          end

          it 'creates customer with integration customers' do
            result = customers_service.create_from_api(
              organization:,
              params: create_args
            )

            expect(result).to be_success
          end
        end

        context 'when there are multiple integration customers of the same type' do
          let(:integration_customers) do
            [
              {
                external_customer_id: '12345',
                integration_type: 'netsuite',
                integration_code: 'code1',
                subsidiary_id: '1',
                sync_with_provider: true
              },
              {
                external_customer_id: '02346',
                integration_type: 'netsuite',
                integration_code: 'code2',
                subsidiary_id: '1',
                sync_with_provider: true
              },
              {
                external_customer_id: '65432',
                integration_type: 'anrok',
                integration_code: 'code3',
                sync_with_provider: true
              }
            ]
          end

          it 'fails to create customer with integration customers' do
            result = customers_service.create_from_api(
              organization:,
              params: create_args
            )

            aggregate_failures do
              expect(result.error).to be_a(BaseService::ValidationFailure)
              expect(result.error.messages.keys).to include(:integration_customers)
              expect(result.error.messages[:integration_customers]).to include('invalid_count_per_integration_type')
            end
          end
        end
      end

      context 'when attached to a subscription' do
        let(:create_args) do
          {
            external_id:,
            name: 'Foo Bar',
            currency: 'CAD'
          }
        end

        before do
          subscription = create(:subscription, customer:)
          customer.update!(currency: subscription.plan.amount_currency)
        end

        it 'fails is we change the subscription' do
          result = customers_service.create_from_api(
            organization:,
            params: create_args
          )

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages.keys).to include(:currency)
            expect(result.error.messages[:currency]).to include('currencies_does_not_match')
          end
        end
      end

      context 'when updating invoice grace period' do
        around { |test| lago_premium!(&test) }

        let(:create_args) do
          {
            external_id:,
            billing_configuration: {invoice_grace_period: 2}
          }
        end

        before do
          allow(Customers::UpdateInvoiceGracePeriodService).to receive(:call)
        end

        it 'calls UpdateInvoiceGracePeriodService' do
          customers_service.create_from_api(organization:, params: create_args)
          expect(Customers::UpdateInvoiceGracePeriodService).to have_received(:call).with(customer:, grace_period: 2)
        end
      end
    end

    context 'with validation error' do
      let(:create_args) do
        {
          name: 'Foo Bar'
        }
      end

      it 'return a failed result' do
        result = customers_service.create_from_api(
          organization:,
          params: create_args
        )

        expect(result).not_to be_success
      end
    end

    context 'with stripe configuration' do
      let(:create_args) do
        {
          external_id: SecureRandom.uuid,
          name: 'Foo Bar',
          billing_configuration: {
            payment_provider: 'stripe',
            payment_provider_code: 'stripe_1',
            provider_customer_id: 'stripe_id'
          }
        }
      end

      context 'when payment provider does not exist' do
        let(:error_messages) { {base: ['payment_provider_not_found']} }

        it 'fails to create customer' do
          result = customers_service.create_from_api(
            organization:,
            params: create_args
          )

          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages).to eq(error_messages)
        end
      end

      context 'when payment provider exists' do
        before { create(:stripe_provider, organization:, code: 'stripe_1') }

        it 'creates a stripe customer' do
          result = customers_service.create_from_api(
            organization:,
            params: create_args
          )

          expect(result).to be_success

          aggregate_failures do
            customer = result.customer
            expect(customer.id).to be_present
            expect(customer.payment_provider).to eq('stripe')

            expect(customer.stripe_customer).to be_present

            stripe_customer = customer.stripe_customer
            expect(stripe_customer.id).to be_present
            expect(stripe_customer.provider_customer_id).to eq('stripe_id')
          end
        end
      end

      context 'when customer already exists' do
        let(:payment_provider) { 'stripe' }
        let(:payment_provider_code) { 'stripe_1' }
        let(:create_args) do
          {
            external_id: SecureRandom.uuid,
            name: 'Foo Bar',
            billing_configuration: {
              payment_provider:,
              payment_provider_code:,
              provider_customer_id: 'stripe_id'
            }
          }
        end
        let(:customer) do
          create(
            :customer,
            organization:,
            external_id: create_args[:external_id],
            email: 'foo@bar.com',
            payment_provider_code: nil,
            payment_provider: nil
          )
        end

        before { customer }

        it 'updates the customer' do
          result = customers_service.create_from_api(
            organization:,
            params: create_args
          )

          aggregate_failures do
            expect(result).to be_success
            expect(result.customer).to eq(customer)

            # NOTE: It should not erase exsting properties
            expect(result.customer.payment_provider).to eq('stripe')
            expect(result.customer.stripe_customer).to be_present

            stripe_customer = result.customer.stripe_customer
            expect(stripe_customer.id).to be_present
            expect(stripe_customer.provider_customer_id).to eq('stripe_id')
          end
        end

        context 'when payment_provider is invalid' do
          let(:payment_provider) { 'foo' }

          it 'updates the customer and reset payment_provider attribute' do
            result = customers_service.create_from_api(
              organization:,
              params: create_args
            )

            aggregate_failures do
              expect(result).to be_success
              expect(result.customer).to eq(customer)

              # NOTE: It should not erase existing properties
              expect(result.customer.payment_provider).to eq(nil)
              expect(result.customer.stripe_customer).not_to be_present
              expect(result.customer.gocardless_customer).not_to be_present
            end
          end
        end

        context 'when payment_provider is not sent' do
          let(:create_args) do
            {
              external_id: SecureRandom.uuid,
              name: 'Foo Bar',
              billing_configuration: {
                sync_with_provider: true
              }
            }
          end

          it 'updates the customer and reset payment_provider attribute' do
            result = customers_service.create_from_api(
              organization:,
              params: create_args
            )

            aggregate_failures do
              expect(result).to be_success
              expect(result.customer).to eq(customer)

              # NOTE: It should not erase existing properties
              expect(result.customer.payment_provider).to eq(nil)
              expect(result.customer.stripe_customer).not_to be_present
            end
          end
        end
      end
    end

    context 'with gocardless configuration' do
      let(:create_args) do
        {
          external_id: SecureRandom.uuid,
          name: 'Foo Bar',
          billing_configuration: {
            payment_provider: 'gocardless',
            provider_customer_id: 'gocardless_id'
          }
        }
      end

      context 'when payment provider does not exist' do
        let(:error_messages) { {base: ['payment_provider_not_found']} }

        it 'fails to create customer' do
          result = customers_service.create_from_api(
            organization:,
            params: create_args
          )

          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages).to eq(error_messages)
        end
      end

      context 'when payment provider exists' do
        before { create(:gocardless_provider, organization:, code: 'gocardless_1') }

        it 'creates a gocardless customer' do
          result = customers_service.create_from_api(
            organization:,
            params: create_args
          )

          expect(result).to be_success

          aggregate_failures do
            customer = result.customer
            expect(customer.id).to be_present
            expect(customer.payment_provider).to eq('gocardless')

            expect(customer.gocardless_customer).to be_present

            gocardless_customer = customer.gocardless_customer
            expect(gocardless_customer.id).to be_present
            expect(gocardless_customer.provider_customer_id).to eq('gocardless_id')
          end
        end
      end
    end

    context 'with unknown payment provider' do
      let(:create_args) do
        {
          external_id: SecureRandom.uuid,
          name: 'Foo Bar',
          billing_configuration: {
            payment_provider: 'foo'
          }
        }
      end

      it 'does not create a payment provider customer' do
        result = customers_service.create_from_api(
          organization:,
          params: create_args
        )

        expect(result).to be_success

        aggregate_failures do
          customer = result.customer
          expect(customer.id).to be_present
          expect(customer.payment_provider).to be_nil
          expect(customer.stripe_customer).to be_nil
          expect(customer.gocardless_customer).to be_nil
        end
      end
    end

    context 'when billing configuration is not provided' do
      it 'creates a payment provider customer' do
        result = customers_service.create_from_api(
          organization:,
          params: create_args
        )

        aggregate_failures do
          expect(result).to be_success

          customer = result.customer
          expect(customer.id).to be_present
          expect(customer.payment_provider).to eq(nil)
          expect(customer.stripe_customer).not_to be_present
          expect(customer.gocardless_customer).not_to be_present
        end
      end

      context 'when customer is updated' do
        before do
          create(
            :customer,
            organization:,
            external_id: create_args[:external_id],
            payment_provider: nil,
            payment_provider_code: nil,
            email: 'foo@bar.com'
          )
        end

        it 'does not create a payment provider customer' do
          result = customers_service.create_from_api(
            organization:,
            params: create_args
          )

          aggregate_failures do
            expect(result).to be_success

            customer = result.customer
            expect(customer.id).to be_present
            expect(customer.payment_provider).to be_nil
            expect(customer.stripe_customer).not_to be_present
            expect(customer.gocardless_customer).not_to be_present
          end
        end
      end
    end

    context 'when organization has eu tax management' do
      let(:eu_auto_tax_service) { instance_double(Customers::EuAutoTaxesService) }

      before do
        create(:tax, organization:, code: 'lago_eu_fr_standard', rate: 20.0)
        organization.update(eu_tax_management: true)

        allow(Customers::EuAutoTaxesService).to receive(:new).and_return(eu_auto_tax_service)
        allow(eu_auto_tax_service).to receive(:call).and_return('lago_eu_fr_standard')
      end

      it 'assigns the right tax to the customer' do
        result = customers_service.create_from_api(
          organization:,
          params: create_args
        )

        aggregate_failures do
          expect(result).to be_success

          tax = result.customer.taxes.first
          expect(tax.code).to eq('lago_eu_fr_standard')
        end
      end
    end
  end

  describe 'create' do
    let(:create_args) do
      {
        external_id: SecureRandom.uuid,
        name: 'Foo Bar',
        organization_id: organization.id,
        currency: 'EUR',
        timezone: 'Europe/Paris',
        invoice_grace_period: 2,
        shipping_address: {
          address_line1: 'line1',
          address_line2: 'line2',
          city: 'Paris',
          zipcode: '123456',
          state: 'foobar',
          country: 'FR'
        }
      }
    end

    before do
      allow(SegmentTrackJob).to receive(:perform_later)
      allow(CurrentContext).to receive(:source).and_return('graphql')
    end

    it 'creates a new customer' do
      result = customers_service.create(**create_args)

      aggregate_failures do
        expect(result).to be_success

        customer = result.customer
        expect(customer.id).to be_present
        expect(customer.organization_id).to eq(organization.id)
        expect(customer.external_id).to eq(create_args[:external_id])
        expect(customer.name).to eq(create_args[:name])
        expect(customer.currency).to eq('EUR')
        expect(customer.timezone).to be_nil
        expect(customer.invoice_grace_period).to be_nil

        shipping_address = create_args[:shipping_address]
        expect(customer.shipping_address_line1).to eq(shipping_address[:address_line1])
        expect(customer.shipping_address_line2).to eq(shipping_address[:address_line2])
        expect(customer.shipping_city).to eq(shipping_address[:city])
        expect(customer.shipping_zipcode).to eq(shipping_address[:zipcode])
        expect(customer.shipping_state).to eq(shipping_address[:state])
        expect(customer.shipping_country).to eq(shipping_address[:country])
      end
    end

    it 'calls SegmentTrackJob' do
      customer = customers_service.create(**create_args).customer

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: 'customer_created',
        properties: {
          customer_id: customer.id,
          created_at: customer.created_at,
          payment_provider: customer.payment_provider,
          organization_id: customer.organization_id
        }
      )
    end

    context 'with premium features' do
      around { |test| lago_premium!(&test) }

      let(:create_args) do
        {
          external_id: SecureRandom.uuid,
          name: 'Foo Bar',
          organization_id: organization.id,
          timezone: 'Europe/Paris',
          invoice_grace_period: 2
        }
      end

      it 'creates a new customer' do
        result = customers_service.create(**create_args)

        aggregate_failures do
          expect(result).to be_success

          customer = result.customer
          expect(customer.timezone).to eq('Europe/Paris')
          expect(customer.invoice_grace_period).to eq(2)
        end
      end
    end

    context 'with metadata' do
      let(:create_args) do
        {
          external_id: SecureRandom.uuid,
          name: 'Foo Bar',
          organization_id: organization.id,
          currency: 'EUR',
          metadata: [
            {
              key: 'manager name',
              value: 'John',
              display_in_invoice: true
            },
            {
              key: 'manager address',
              value: 'Test',
              display_in_invoice: false
            }
          ]
        }
      end

      it 'creates customer with metadata' do
        result = customers_service.create(**create_args)

        aggregate_failures do
          expect(result).to be_success

          customer = result.customer
          expect(customer.metadata.count).to eq(2)
        end
      end
    end

    context 'when customer already exists' do
      let(:customer) do
        create(:customer, organization:, external_id: create_args[:external_id])
      end

      before { customer }

      it 'return a failed result' do
        result = customers_service.create(**create_args)

        expect(result).not_to be_success
      end
    end

    context 'with validation error' do
      let(:create_args) do
        {
          name: 'Foo Bar'
        }
      end

      it 'return a failed result' do
        result = customers_service.create(**create_args)

        expect(result).not_to be_success
      end
    end

    context 'with stripe payment provider' do
      before do
        create(
          :stripe_provider,
          organization:
        )
      end

      context 'with provider customer id' do
        let(:create_args) do
          {
            external_id: SecureRandom.uuid,
            name: 'Foo Bar',
            organization_id: organization.id,
            payment_provider: 'stripe',
            provider_customer: {provider_customer_id: 'cus_12345'}
          }
        end

        it 'creates a payment provider customer' do
          result = customers_service.create(**create_args)

          aggregate_failures do
            expect(result).to be_success

            customer = result.customer
            expect(customer.id).to be_present
            expect(customer.payment_provider).to eq('stripe')
            expect(customer.stripe_customer).to be_present
            expect(customer.stripe_customer.provider_customer_id).to eq('cus_12345')
          end
        end
      end
    end

    context 'with gocardless payment provider' do
      before do
        create(
          :gocardless_provider,
          organization:
        )
      end

      context 'with provider customer id' do
        let(:create_args) do
          {
            external_id: SecureRandom.uuid,
            name: 'Foo Bar',
            organization_id: organization.id,
            payment_provider: 'gocardless',
            provider_customer: {provider_customer_id: 'cus_12345'}
          }
        end

        it 'creates a payment provider customer' do
          result = customers_service.create(**create_args)

          aggregate_failures do
            expect(result).to be_success

            customer = result.customer
            expect(customer.id).to be_present
            expect(customer.payment_provider).to eq('gocardless')
            expect(customer.gocardless_customer).to be_present
            expect(customer.gocardless_customer.provider_customer_id).to eq('cus_12345')
          end
        end
      end

      context 'with sync option enabled' do
        let(:create_args) do
          {
            external_id: SecureRandom.uuid,
            name: 'Foo Bar',
            organization_id: organization.id,
            payment_provider: 'gocardless',
            provider_customer: {sync_with_provider: true}
          }
        end

        it 'creates a payment provider customer' do
          result = customers_service.create(**create_args)

          aggregate_failures do
            expect(result).to be_success

            customer = result.customer
            expect(customer.id).to be_present
            expect(customer.payment_provider).to eq('gocardless')
            expect(customer.gocardless_customer).to be_present
          end
        end
      end
    end

    context 'when organization has eu tax management' do
      let(:eu_auto_tax_service) { instance_double(Customers::EuAutoTaxesService) }

      before do
        create(:tax, organization:, code: 'lago_eu_fr_standard', rate: 20.0)
        organization.update(eu_tax_management: true)

        allow(Customers::EuAutoTaxesService).to receive(:new).and_return(eu_auto_tax_service)
        allow(eu_auto_tax_service).to receive(:call).and_return('lago_eu_fr_standard')
      end

      it 'assigns the right tax to the customer' do
        result = customers_service.create(**create_args)

        aggregate_failures do
          expect(result).to be_success

          tax = result.customer.taxes.first
          expect(tax.code).to eq('lago_eu_fr_standard')
        end
      end
    end
  end
end
