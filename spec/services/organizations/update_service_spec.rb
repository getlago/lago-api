# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Organizations::UpdateService do
  subject(:organization_update_service) { described_class.new(organization) }

  let(:organization) { create(:organization) }

  describe '.update' do
    it 'updates the organization' do
      result = organization_update_service.update(
        webhook_url: 'http://foo.bar',
        vat_rate: 12.5,
        legal_name: 'Foobar',
        legal_number: '1234',
        email: 'foo@bar.com',
        address_line1: 'Line 1',
        address_line2: 'Line 2',
        state: 'Foobar',
        zipcode: 'FOO1234',
        city: 'Foobar',
        country: 'FR',
        invoice_footer: 'invoice footer',
      )

      aggregate_failures do
        expect(result.organization.webhook_url).to eq('http://foo.bar')
        expect(result.organization.vat_rate).to eq(12.5)
        expect(result.organization.legal_name).to eq('Foobar')
        expect(result.organization.legal_number).to eq('1234')
        expect(result.organization.email).to eq('foo@bar.com')
        expect(result.organization.address_line1).to eq('Line 1')
        expect(result.organization.address_line2).to eq('Line 2')
        expect(result.organization.state).to eq('Foobar')
        expect(result.organization.zipcode).to eq('FOO1234')
        expect(result.organization.city).to eq('Foobar')
        expect(result.organization.country).to eq('FR')
        expect(result.organization.timezone).to eq('UTC')
        expect(result.organization.invoice_footer).to eq('invoice footer')
      end
    end

    context 'with premium features' do
      around { |test| lago_premium!(&test) }

      it 'updates the organization' do
        result = organization_update_service.update(
          timezone: 'Europe/Paris',
        )

        aggregate_failures do
          expect(result.organization.timezone).to eq('Europe/Paris')
        end
      end

      context 'when updating invoice grace period' do
        let(:customer) { create(:customer, organization:) }

        let(:invoice_to_be_finalized) do
          create(:invoice, status: :draft, customer:, created_at: DateTime.parse('19 Jun 2022'), organization:)
        end

        let(:invoice_to_not_be_finalized) do
          create(:invoice, status: :draft, customer:, created_at: DateTime.parse('21 Jun 2022'), organization:)
        end

        before do
          invoice_to_be_finalized
          invoice_to_not_be_finalized
          allow(Invoices::FinalizeService).to receive(:call)
        end

        it 'finalizes corresponding draft invoices' do
          current_date = DateTime.parse('22 Jun 2022')

          travel_to(current_date) do
            result = organization_update_service.update(invoice_grace_period: 2)

            expect(result.organization.invoice_grace_period).to eq(2)
            expect(Invoices::FinalizeService).not_to have_received(:call).with(invoice: invoice_to_not_be_finalized)
            expect(Invoices::FinalizeService).to have_received(:call).with(invoice: invoice_to_be_finalized)
          end
        end
      end
    end

    context 'with base64 logo' do
      let(:base64_logo) do
        logo_file = File.open(Rails.root.join('spec/factories/images/logo.png')).read
        base64_logo = Base64.encode64(logo_file)

        "data:image/png;base64,#{base64_logo}"
      end

      it 'updates the organization with logo' do
        result = organization_update_service.update(
          logo: base64_logo,
        )

        expect(result.organization.logo.blob).not_to be_nil
      end
    end
  end

  describe 'update_from_api' do
    let(:country) { 'pl' }
    let(:update_args) do
      {
        webhook_url: 'http://test.example',
        country:,
        address_line1: 'address1',
        address_line2: 'address2',
        state: 'state',
        zipcode: '10000',
        email: 'mail@example.com',
        city: 'test_city',
        legal_name: 'test1',
        legal_number: '123',
        billing_configuration: {
          invoice_footer: 'footer',
          vat_rate: 20,
        },
      }
    end

    it 'updates an organization' do
      result = organization_update_service.update_from_api(params: update_args)

      aggregate_failures do
        expect(result).to be_success

        organization_response = result.organization
        expect(organization_response.name).to eq(organization.name)
        expect(organization_response.webhook_url).to eq(update_args[:webhook_url])

        billing = update_args[:billing_configuration]
        expect(organization_response.invoice_footer).to eq(billing[:invoice_footer])
        expect(organization_response.vat_rate).to eq(billing[:vat_rate])
      end
    end

    context 'with premium features' do
      around { |test| lago_premium!(&test) }

      let(:update_args) do
        {
          timezone: 'Europe/Paris',
        }
      end

      it 'updates an organization' do
        result = organization_update_service.update_from_api(params: update_args)

        aggregate_failures do
          expect(result).to be_success

          organization_response = result.organization
          expect(organization_response.timezone).to eq(update_args[:timezone])
        end
      end

      context 'when updating invoice grace period' do
        let(:update_args) do
          { billing_configuration: { invoice_grace_period: 2 } }
        end

        let(:customer) { create(:customer, organization:) }

        let(:invoice_to_be_finalized) do
          create(:invoice, status: :draft, customer:, created_at: DateTime.parse('19 Jun 2022'), organization:)
        end

        let(:invoice_to_not_be_finalized) do
          create(:invoice, status: :draft, customer:, created_at: DateTime.parse('21 Jun 2022'), organization:)
        end

        before do
          invoice_to_be_finalized
          invoice_to_not_be_finalized
          allow(Invoices::FinalizeService).to receive(:call)
        end

        it 'finalizes corresponding draft invoices' do
          current_date = DateTime.parse('22 Jun 2022')

          travel_to(current_date) do
            result = organization_update_service.update_from_api(params: update_args)

            expect(result.organization.invoice_grace_period).to eq(2)
            expect(Invoices::FinalizeService).not_to have_received(:call).with(invoice: invoice_to_not_be_finalized)
            expect(Invoices::FinalizeService).to have_received(:call).with(invoice: invoice_to_be_finalized)
          end
        end
      end
    end

    context 'with validation errors' do
      let(:country) { '---' }

      it 'returns an error' do
        result = organization_update_service.update_from_api(params: update_args)

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:country]).to eq(['not_a_valid_country_code'])
        end
      end
    end
  end
end
