# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Customers::UpdateService, type: :service do
  subject(:customers_service) { described_class.new(customer:, args: update_args) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:payment_provider_code) { 'stripe_1' }

  describe 'update' do
    let(:customer) { create(:customer, organization:, payment_provider: 'stripe', payment_provider_code:) }
    let(:external_id) { SecureRandom.uuid }

    let(:update_args) do
      {
        id: customer.id,
        name: 'Updated customer name',
        firstname: 'Updated customer firstname',
        lastname: 'Updated customer lastname',
        customer_type: 'individual',
        tax_identification_number: '2246',
        net_payment_term: 8,
        external_id:,
        shipping_address: {
          city: 'Paris'
        }
      }
    end

    it 'updates a customer' do
      result = customers_service.call

      updated_customer = result.customer
      aggregate_failures do
        expect(updated_customer.name).to eq(update_args[:name])
        expect(updated_customer.firstname).to eq(update_args[:firstname])
        expect(updated_customer.lastname).to eq(update_args[:lastname])
        expect(updated_customer.customer_type).to eq(update_args[:customer_type])
        expect(updated_customer.tax_identification_number).to eq(update_args[:tax_identification_number])

        shipping_address = update_args[:shipping_address]
        expect(updated_customer.shipping_city).to eq(shipping_address[:city])
      end
    end

    context 'with premium features' do
      around { |test| lago_premium!(&test) }

      let(:update_args) do
        {
          id: customer.id,
          timezone: 'Europe/Paris',
          billing_configuration: {
            invoice_grace_period: 3
          }
        }
      end

      it 'updates a customer' do
        result = customers_service.call

        updated_customer = result.customer
        aggregate_failures do
          expect(updated_customer.timezone).to eq('Europe/Paris')

          billing = update_args[:billing_configuration]
          expect(updated_customer.invoice_grace_period).to eq(billing[:invoice_grace_period])
        end
      end
    end

    context 'with metadata' do
      let(:customer_metadata) { create(:customer_metadata, customer:) }
      let(:another_customer_metadata) { create(:customer_metadata, customer:, key: 'test', value: '1') }
      let(:update_args) do
        {
          id: customer.id,
          name: 'Updated customer name',
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
        result = customers_service.call

        metadata_keys = result.customer.metadata.pluck(:key)
        metadata_ids = result.customer.metadata.pluck(:id)

        expect(result.customer.metadata.count).to eq(2)
        expect(metadata_keys).to eq(['new key', 'Added key'])
        expect(metadata_ids).to include(customer_metadata.id)
        expect(metadata_ids).not_to include(another_customer_metadata.id)
      end
    end

    context 'with validation error' do
      let(:external_id) { nil }

      it 'returns an error' do
        result = customers_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:external_id]).to eq(['value_is_mandatory'])
        end
      end
    end

    context 'when attached to a subscription' do
      before do
        subscription = create(:subscription, customer:)
        customer.update!(currency: subscription.plan.amount_currency)
      end

      it 'updates only the name' do
        result = customers_service.call

        updated_customer = result.customer
        aggregate_failures do
          expect(updated_customer.name).to eq('Updated customer name')
          expect(updated_customer.external_id).to eq(customer.external_id)
        end
      end

      context 'when updating the currency' do
        let(:update_args) do
          {
            id: customer.id,
            currency: 'CAD'
          }
        end

        it 'fails' do
          result = customers_service.call

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages.keys).to include(:currency)
            expect(result.error.messages[:currency]).to include('currencies_does_not_match')
          end
        end
      end
    end

    context 'when updating payment provider' do
      let(:update_args) do
        {
          id: customer.id,
          name: 'Updated customer name',
          external_id:,
          payment_provider: 'stripe',
          payment_provider_code:
        }
      end

      before do
        create(:stripe_provider, organization: customer.organization, code: payment_provider_code)

        allow(PaymentProviderCustomers::UpdateService)
          .to receive(:call)
          .with(customer)
          .and_return(BaseService::Result.new)
      end

      it 'creates a payment provider customer' do
        result = customers_service.call
        expect(result).to be_success

        updated_customer = result.customer
        aggregate_failures do
          expect(updated_customer.payment_provider).to eq('stripe')
          expect(updated_customer.stripe_customer).to be_present
        end
      end

      it 'does not call payment provider customer update service' do
        customers_service.call
        expect(PaymentProviderCustomers::UpdateService).not_to have_received(:call).with(customer)
      end

      context 'with provider customer id' do
        let(:update_args) do
          {
            id: customer.id,
            external_id: SecureRandom.uuid,
            name: 'Foo Bar',
            organization_id: organization.id,
            payment_provider: 'stripe',
            provider_customer: {provider_customer_id: 'cus_12345'}
          }
        end

        it 'calls payment provider customer update service' do
          customers_service.call
          expect(PaymentProviderCustomers::UpdateService).to have_received(:call).with(customer)
        end

        it 'creates a payment provider customer' do
          result = customers_service.call

          aggregate_failures do
            expect(result).to be_success

            customer = result.customer
            expect(customer.id).to be_present
            expect(customer.payment_provider).to eq('stripe')
            expect(customer.stripe_customer).to be_present
            expect(customer.stripe_customer.provider_customer_id).to eq('cus_12345')
          end
        end

        context 'when removing a provider customer id' do
          let(:update_args) do
            {
              id: customer.id,
              external_id: SecureRandom.uuid,
              name: 'Foo Bar',
              organization_id: organization.id,
              payment_provider: nil,
              provider_customer: {provider_customer_id: nil}
            }
          end

          let(:stripe_customer) { create(:stripe_customer, customer:) }

          before do
            stripe_customer
            customer.update!(payment_provider: 'stripe')
          end

          it 'removes the provider customer id' do
            result = customers_service.call

            aggregate_failures do
              expect(result).to be_success

              customer = result.customer
              expect(customer.id).to eq(customer.id)
              expect(customer.payment_provider).to be_nil

              expect(customer.stripe_customer).to eq(stripe_customer)
              expect(customer.stripe_customer.provider_customer_id).to be_nil
            end
          end
        end
      end
    end

    context 'when partialy updating' do
      let(:stripe_customer) { create(:stripe_customer, customer:, provider_payment_methods: %w[sepa_debit]) }

      let(:update_args) do
        {
          id: customer.id,
          invoice_grace_period: 8
        }
      end

      around { |test| lago_premium!(&test) }
      before { stripe_customer }

      it 'updates only the updated args' do
        result = customers_service.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.customer.invoice_grace_period).to eq(update_args[:invoice_grace_period])

          expect(result.customer.stripe_customer.provider_payment_methods).to eq(%w[sepa_debit])
        end
      end
    end

    context 'when updating net payment term' do
      it 'updates the net payment term of all draft invoices' do
        create(:invoice, :draft, customer:, net_payment_term: 30)
        create(:invoice, customer:, net_payment_term: 30)
        create(:invoice, :draft, customer:, net_payment_term: 30)

        result = customers_service.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.customer.invoices.draft.pluck(:net_payment_term)).to eq([8, 8])
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
        result = customers_service.call

        aggregate_failures do
          expect(result).to be_success

          tax = result.customer.taxes.first
          expect(tax.code).to eq('lago_eu_fr_standard')
        end
      end
    end

    context "when dunning campaign data is provided" do
      let(:customer) do
        create(
          :customer,
          organization:,
          applied_dunning_campaign: dunning_campaign,
          last_dunning_campaign_attempt: 3,
          last_dunning_campaign_attempt_at: 2.days.ago
        )
      end
      let(:dunning_campaign) { create(:dunning_campaign) }

      let(:update_args) do
        {
          id: customer.id,
          applied_dunning_campaign_id: dunning_campaign.id,
          exclude_from_dunning_campaign: true
        }
      end

      it "does not update auto dunning config", :aggregate_failures do
        expect { customers_service.call }
          .to not_change(customer, :applied_dunning_campaign_id)
          .and not_change(customer, :exclude_from_dunning_campaign)
          .and not_change(customer, :last_dunning_campaign_attempt)
          .and not_change { customer.last_dunning_campaign_attempt_at.iso8601 }

        expect(customers_service.call).to be_success
      end

      context "with auto_dunning premium integration" do
        let(:customer) do
          create(
            :customer,
            organization:,
            exclude_from_dunning_campaign: true,
            last_dunning_campaign_attempt: 3,
            last_dunning_campaign_attempt_at: 2.days.ago
          )
        end

        let(:organization) do
          create(:organization, premium_integrations: ["auto_dunning"])
        end

        let(:membership) { create(:membership, organization: organization) }

        let(:update_args) do
          {applied_dunning_campaign_id: dunning_campaign.id}
        end

        around { |test| lago_premium!(&test) }

        it "updates auto dunning config", :aggregate_failures do
          expect { customers_service.call }
            .to change(customer, :applied_dunning_campaign_id).to(dunning_campaign.id)
            .and change(customer, :exclude_from_dunning_campaign).to(false)
            .and change(customer, :last_dunning_campaign_attempt).to(0)
            .and change(customer, :last_dunning_campaign_attempt_at).to(nil)

          expect(customers_service.call).to be_success
        end

        context "with exclude from dunning campaign" do
          let(:customer) do
            create(
              :customer,
              organization:,
              applied_dunning_campaign: dunning_campaign,
              last_dunning_campaign_attempt: 3,
              last_dunning_campaign_attempt_at: 2.days.ago
            )
          end

          let(:update_args) do
            {exclude_from_dunning_campaign: true}
          end

          it "updates auto dunning config", :aggregate_failures do
            expect { customers_service.call }
              .to change(customer, :applied_dunning_campaign_id).to(nil)
              .and change(customer, :exclude_from_dunning_campaign).to(true)
              .and change(customer, :last_dunning_campaign_attempt).to(0)
              .and change(customer, :last_dunning_campaign_attempt_at).to(nil)

            expect(customers_service.call).to be_success
          end
        end

        context "with applied_dunning_campaign_id nil" do
          let(:customer) do
            create(
              :customer,
              organization:,
              applied_dunning_campaign: dunning_campaign,
              exclude_from_dunning_campaign: false,
              last_dunning_campaign_attempt: 3,
              last_dunning_campaign_attempt_at: 2.days.ago
            )
          end

          let(:update_args) { {applied_dunning_campaign_id: nil} }

          it "updates auto dunning config", :aggregate_failures do
            expect { customers_service.call }
              .to change(customer, :applied_dunning_campaign_id).to(nil)
              .and not_change(customer, :exclude_from_dunning_campaign)
              .and change(customer, :last_dunning_campaign_attempt).to(0)
              .and change(customer, :last_dunning_campaign_attempt_at).to(nil)

            expect(customers_service.call).to be_success
          end
        end

        context "when dunning campaign can not be found" do
          let(:customer) do
            create(
              :customer,
              organization:,
              applied_dunning_campaign: dunning_campaign,
              exclude_from_dunning_campaign: false,
              last_dunning_campaign_attempt: 3,
              last_dunning_campaign_attempt_at: 2.days.ago
            )
          end

          let(:update_args) { {applied_dunning_campaign_id: "not_found_id"} }

          it "does not update auto dunning config", :aggregate_failures do
            expect { customers_service.call }
              .to not_change(customer, :applied_dunning_campaign_id)
              .and not_change(customer, :exclude_from_dunning_campaign)
              .and not_change(customer, :last_dunning_campaign_attempt)
              .and not_change(customer, :last_dunning_campaign_attempt_at)

            result = customers_service.call

            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::NotFoundFailure)
            expect(result.error.error_code).to eq("dunning_campaign_not_found")
          end
        end
      end
    end
  end
end
