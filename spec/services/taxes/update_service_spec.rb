# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Taxes::UpdateService, type: :service do
  subject(:update_service) { described_class.new(tax:, params:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:tax) { create(:tax, organization:) }

  let(:customer) { create(:customer, organization:) }

  describe '#call' do
    before { tax }

    let(:params) do
      {
        code: 'updated code',
        rate: 15.0,
        description: 'updated desc'
      }
    end

    it 'updates the tax' do
      result = update_service.call

      expect(result).to be_success
      expect(result.tax).to have_attributes(
        name: tax.name,
        code: params[:code],
        rate: params[:rate],
        description: params[:description],
      )
    end

    it 'returns tax in the result' do
      result = update_service.call
      expect(result.tax).to be_a(Tax)
    end

    context 'when applied_to_organization is updated to false' do
      let(:params) do
        {applied_to_organization: false}
      end

      it 'marks invoices as ready to be refreshed' do
        draft_invoice = create(:invoice, :draft, organization:, customer:)

        expect { update_service.call }.to change { draft_invoice.reload.ready_to_be_refreshed }.to(true)
      end
    end

    context 'when applied_to_organization is updated to true' do
      let(:tax) { create(:tax, organization:, applied_to_organization: false) }
      let(:params) do
        {applied_to_organization: true}
      end

      it 'marks invoices as ready to be refreshed' do
        draft_invoice = create(:invoice, :draft, organization:, customer:)

        expect { update_service.call }.to change { draft_invoice.reload.ready_to_be_refreshed }.to(true)
      end
    end

    it 'marks invoices as ready to be refreshed' do
      draft_invoice = create(:invoice, :draft, organization:, customer:)

      expect { update_service.call }.to change { draft_invoice.reload.ready_to_be_refreshed }.to(true)
    end

    context 'when tax is not found' do
      let(:tax) { nil }

      it 'returns an error' do
        result = update_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.error_code).to eq('tax_not_found')
        end
      end
    end

    context 'with validation error' do
      let(:params) do
        {
          id: tax.id,
          name: nil,
          code: 'code',
          amount_cents: 100,
          amount_currency: 'EUR'
        }
      end

      it 'returns an error' do
        result = update_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:name]).to eq(['value_is_mandatory'])
        end
      end
    end
  end
end
