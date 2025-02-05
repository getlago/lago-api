# frozen_string_literal: true

require 'rails_helper'
require 'valvat'

RSpec.describe Customers::EuAutoTaxesService, type: :service do
  subject(:eu_tax_service) { described_class.new(customer:, new_record:, tax_attributes_changed:) }

  let(:organization) { create(:organization, country: 'FR', eu_tax_management: true) }
  let(:customer) { create(:customer, organization:, zipcode: nil) }
  let(:new_record) { true }
  let(:tax_attributes_changed) { true }

  describe '.call' do
    context 'with B2B organization' do
      let(:vies_service) { instance_double(Valvat) }
      let(:vies_response) { {} }

      before do
        allow(Valvat).to receive(:new).and_return(vies_service)
        allow(vies_service).to receive(:exists?).and_return(vies_response)
      end

      context 'when eu_tax_management is false' do
        let(:organization) { create(:organization, country: 'FR', eu_tax_management: false) }

        it 'returns error' do
          result = eu_tax_service.call

          expect(result).not_to be_success
          expect(result.error.code).to eq('eu_tax_not_applicable')
        end
      end

      context 'when customer is updated and there are eu taxes' do
        let(:new_record) { false }
        let(:tax_attributes_changed) { false }
        let(:applied_tax) { create(:customer_applied_tax, tax:, customer:) }
        let(:tax) { create(:tax, organization:, code: 'lago_eu_tax_exempt') }

        before { applied_tax }

        it 'returns error' do
          result = eu_tax_service.call

          expect(result).not_to be_success
          expect(result.error.code).to eq('eu_tax_not_applicable')
        end
      end

      context 'when customer is updated and there are no eu taxes' do
        let(:new_record) { false }
        let(:tax_attributes_changed) { false }
        let(:applied_tax) { create(:customer_applied_tax, tax:, customer:) }
        let(:tax) { create(:tax, organization:, code: 'unknown_eu_tax_exempt') }
        let(:vies_response) do
          {
            country_code: 'FR'
          }
        end

        before { applied_tax }

        it 'returns the organization country tax code' do
          result = eu_tax_service.call

          expect(result.tax_code).to eq('lago_eu_fr_standard')
        end
      end

      context 'with same country as the organization' do
        let(:vies_response) do
          {
            country_code: 'FR'
          }
        end

        it 'returns the organization country tax code' do
          result = eu_tax_service.call

          expect(result.tax_code).to eq('lago_eu_fr_standard')
        end

        it 'enqueues a SendWebhookJob' do
          eu_tax_service.call

          expect(SendWebhookJob).to have_been_enqueued
            .with('customer.vies_check', customer, vies_check: vies_response)
        end
      end

      context 'with a different country from the organization one' do
        let(:vies_response) do
          {
            country_code: 'DE'
          }
        end

        it 'returns the reverse charge tax' do
          result = eu_tax_service.call

          expect(result.tax_code).to eq('lago_eu_reverse_charge')
        end
      end

      context 'when country has exceptions' do
        let(:vies_response) do
          {
            country_code: 'FR'
          }
        end

        context 'when customer has no zipcode' do
          it 'returns the customer country standard tax' do
            result = eu_tax_service.call
            expect(result.tax_code).to eq('lago_eu_fr_standard')
          end
        end

        context 'when customer has a zipcode' do
          context 'when zipcode has applicable exceptions' do
            before do
              customer.update(zipcode: '97412')
            end

            it 'returns the exception tax code' do
              result = eu_tax_service.call
              expect(result.tax_code).to eq('lago_eu_fr_exception_reunion')
            end
          end

          context 'when zipcode has no applicable exceptions' do
            before do
              customer.update(zipcode: '12345')
            end

            it 'returns the customer counrty standard tax' do
              result = eu_tax_service.call
              expect(result.tax_code).to eq('lago_eu_fr_standard')
            end
          end
        end
      end
    end

    context 'with non B2B' do
      let(:vies_response) { false }

      context 'when the customer has no country' do
        before do
          customer.update(country: nil)
        end

        it 'returns the organization country tax code' do
          result = eu_tax_service.call

          expect(result.tax_code).to eq('lago_eu_fr_standard')
        end
      end

      context 'when the customer country is in europe' do
        before do
          customer.update(country: 'DE')
        end

        it 'returns the customer country tax code' do
          result = eu_tax_service.call

          expect(result.tax_code).to eq('lago_eu_de_standard')
        end
      end

      context 'when the customer country is out of europe' do
        before do
          customer.update(country: 'US')
        end

        it 'returns the tax exempt tax code' do
          result = eu_tax_service.call

          expect(result.tax_code).to eq('lago_eu_tax_exempt')
        end
      end
    end
  end
end
