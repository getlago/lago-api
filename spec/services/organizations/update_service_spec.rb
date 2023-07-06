# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Organizations::UpdateService do
  subject(:update_service) { described_class.new(organization:, params:) }

  let(:organization) { create(:organization) }

  let(:timezone) { nil }
  let(:email_settings) { [] }
  let(:invoice_grace_period) { 0 }
  let(:logo) { nil }
  let(:country) { 'FR' }

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
      country:,
      timezone:,
      logo:,
      email_settings:,
      billing_configuration: {
        invoice_footer: 'invoice footer',
        document_locale: 'fr',
        invoice_grace_period:,
      },
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
        expect(result.organization.timezone).to eq('UTC')

        expect(result.organization.invoice_footer).to eq('invoice footer')
        expect(result.organization.document_locale).to eq('fr')
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
        logo_file = File.open(Rails.root.join('spec/factories/images/logo.png')).read
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

    context 'with legacy vat_rate' do
      let(:vat_rate) { 12.5 }
      let(:params) do
        {
          webhook_url: 'http://foo.bar',
          legal_name: 'Foobar',
          legal_number: '1234',
          email: 'foo@bar.com',
          address_line1: 'Line 1',
          address_line2: 'Line 2',
          state: 'Foobar',
          zipcode: 'FOO1234',
          city: 'Foobar',
          country:,
          timezone:,
          logo:,
          email_settings:,
          billing_configuration: {
            vat_rate:,
            invoice_footer: 'invoice footer',
            document_locale: 'fr',
            invoice_grace_period:,
          },
        }
      end

      it 'assigns the vat_rate and creates a tax_rate' do
        result = update_service.call

        aggregate_failures do
          expect(result.organization.vat_rate).to eq(12.5)

          expect(result.organization.taxes.count).to eq(1)

          tax_rate = result.organization.taxes.first
          expect(tax_rate.rate).to eq(12.5)
        end
      end

      context 'when organization already have a tax rate' do
        before { create(:tax, organization:, rate: 14) }

        it 'create a new tax_rate' do
          result = update_service.call

          aggregate_failures do
            expect(result.organization.vat_rate).to eq(12.5)

            expect(result.organization.taxes.count).to eq(2)
            expect(result.organization.taxes.applied_to_organization.count).to eq(1)

            tax_rate = result.organization.taxes.applied_to_organization.first
            expect(tax_rate.rate).to eq(12.5)
          end
        end

        context 'with vat_rate equals to 0' do
          let(:vat_rate) { 0 }

          it 'toggle the applied_to_organization flag' do
            result = update_service.call

            aggregate_failures do
              expect(result.organization.vat_rate).to eq(0)

              expect(result.organization.taxes.count).to eq(1)
              expect(result.organization.taxes.applied_to_organization.count).to eq(0)
            end
          end
        end
      end

      context 'when organization have multiple tax rates' do
        before do
          create(:tax, organization:, rate: 14)
          create(:tax, organization:, rate: 15)
        end

        it 'raises a validation error' do
          result = update_service.call

          aggregate_failures do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
            expect(result.error.messages[:vat_rate]).to eq(['multiple_taxes'])
          end
        end
      end
    end
  end
end
