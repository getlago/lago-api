# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Organizations::UpdateService do
  subject(:update_service) { described_class.new(organization:, params:) }

  let(:organization) { create(:organization) }

  let(:timezone) { nil }
  let(:email_settings) { [] }
  let(:invoice_grace_period) { 0 }
  let(:logo) { nil }
  let(:country) { 'fr' }

  let(:params) do
    {
      legal_name: 'Foobar',
      legal_number: '1234',
      tax_identification_number: '2246',
      email: 'foo@bar.com',
      address_line1: 'Line 1',
      address_line2: 'Line 2',
      state: 'Foobar',
      zipcode: 'FOO1234',
      city: 'Foobar',
      default_currency: 'EUR',
      country:,
      timezone:,
      logo:,
      email_settings:,
      billing_configuration: {
        invoice_footer: 'invoice footer',
        document_locale: 'fr',
        invoice_grace_period:
      }
    }
  end

  describe '#call' do
    it 'updates the organization' do
      result = update_service.call

      aggregate_failures do
        expect(result.organization.legal_name).to eq('Foobar')
        expect(result.organization.legal_number).to eq('1234')
        expect(result.organization.tax_identification_number).to eq('2246')
        expect(result.organization.email).to eq('foo@bar.com')
        expect(result.organization.address_line1).to eq('Line 1')
        expect(result.organization.address_line2).to eq('Line 2')
        expect(result.organization.state).to eq('Foobar')
        expect(result.organization.zipcode).to eq('FOO1234')
        expect(result.organization.city).to eq('Foobar')
        expect(result.organization.country).to eq('FR')
        expect(result.organization.default_currency).to eq('EUR')
        expect(result.organization.timezone).to eq('UTC')

        expect(result.organization.invoice_footer).to eq('invoice footer')
        expect(result.organization.document_locale).to eq('fr')
      end
    end

    context 'when document_number_prefix is sent' do
      before { params[:document_number_prefix] = 'abc' }

      it 'converts document_number_prefix to upcase version' do
        result = update_service.call

        aggregate_failures do
          expect(result.organization.document_number_prefix).to eq('ABC')
        end
      end
    end

    context 'when document_number_prefix is invalid' do
      before { params[:document_number_prefix] = 'aaaaaaaaaaaaaaa' }

      it 'returns an error' do
        result = update_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:document_number_prefix]).to eq(['value_is_too_long'])
        end
      end
    end

    context 'with premium features' do
      around { |test| lago_premium!(&test) }

      let(:timezone) { 'Europe/Paris' }
      let(:email_settings) { ['invoice.finalized'] }

      it 'updates the organization' do
        result = update_service.call

        expect(result.organization.timezone).to eq('Europe/Paris')
      end

      context 'when updating invoice grace period' do
        let(:customer) { create(:customer, organization:) }

        let(:invoice_to_be_finalized) do
          create(:invoice, status: :draft, customer:, created_at: DateTime.parse('19 Jun 2022'), organization:)
        end

        let(:invoice_to_not_be_finalized) do
          create(:invoice, status: :draft, customer:, created_at: DateTime.parse('21 Jun 2022'), organization:)
        end

        let(:invoice_grace_period) { 2 }

        before do
          invoice_to_be_finalized
          invoice_to_not_be_finalized
          allow(Invoices::FinalizeService).to receive(:call)
        end

        it 'finalizes corresponding draft invoices' do
          current_date = DateTime.parse('22 Jun 2022')

          travel_to(current_date) do
            result = update_service.call

            aggregate_failures do
              expect(result.organization.invoice_grace_period).to eq(2)
              expect(Invoices::FinalizeService).not_to have_received(:call).with(invoice: invoice_to_not_be_finalized)
              expect(Invoices::FinalizeService).to have_received(:call).with(invoice: invoice_to_be_finalized)
            end
          end
        end
      end
    end

    context 'with base64 logo' do
      let(:logo) do
        logo_file = File.read(Rails.root.join('spec/factories/images/logo.png'))
        base64_logo = Base64.encode64(logo_file)

        "data:image/png;base64,#{base64_logo}"
      end

      it 'updates the organization with logo' do
        result = update_service.call
        expect(result.organization.logo.blob).not_to be_nil
      end
    end

    context 'with validation errors' do
      let(:country) { '---' }

      it 'returns an error' do
        result = update_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:country]).to eq(['not_a_valid_country_code'])
        end
      end
    end

    context 'with eu tax management' do
      context 'with org within the EU' do
        let(:params) { {eu_tax_management: true, country: 'fr'} }
        let(:tax_auto_generate_service) { instance_double(Taxes::AutoGenerateService) }

        before do
          allow(Taxes::AutoGenerateService).to receive(:new).and_return(tax_auto_generate_service)
          allow(tax_auto_generate_service).to receive(:call)
        end

        it 'calls the taxes auto generate service' do
          result = update_service.call

          aggregate_failures do
            expect(result).to be_success
            expect(tax_auto_generate_service).to have_received(:call)
          end
        end
      end

      context 'with org outside the EU' do
        let(:params) { {eu_tax_management: true, country: 'us'} }
        let(:tax_auto_generate_service) { instance_double(Taxes::AutoGenerateService) }

        before do
          allow(Taxes::AutoGenerateService).to receive(:new).and_return(tax_auto_generate_service)
          allow(tax_auto_generate_service).to receive(:call)
        end

        it 'calls the taxes auto generate service' do
          result = update_service.call

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages).to eq({eu_tax_management: ['org_must_be_in_eu']})
            expect(tax_auto_generate_service).not_to have_received(:call)
          end
        end
      end

      context 'with org is outside the EU but feature is already enabled' do
        let(:params) { {eu_tax_management: false} }
        let(:tax_auto_generate_service) { instance_double(Taxes::AutoGenerateService) }

        before do
          organization.country = 'us'
          organization.eu_tax_management = true
          allow(Taxes::AutoGenerateService).to receive(:new).and_return(tax_auto_generate_service)
          allow(tax_auto_generate_service).to receive(:call)
        end

        it 'can disable eu_tax_management' do
          result = update_service.call

          aggregate_failures do
            expect(result).to be_success
            expect(tax_auto_generate_service).not_to have_received(:call)
          end
        end
      end
    end
  end
end
