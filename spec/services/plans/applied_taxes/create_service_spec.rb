# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Plans::AppliedTaxes::CreateService, type: :service do
  subject(:create_service) { described_class.new(plan:, tax:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:, organization:) }
  let(:plan) { subscription.plan }
  let(:tax) { create(:tax, organization:) }

  before { subscription }

  describe '#call' do
    it 'creates an applied tax' do
      expect { create_service.call }.to change(Plan::AppliedTax, :count).by(1)
    end

    it 'refreshes draft invoices' do
      draft_invoice = create(:invoice, :draft, organization:)
      create(:invoice_subscription, invoice: draft_invoice, subscription:)

      expect do
        create_service.call
      end.to have_enqueued_job(Invoices::RefreshBatchJob).with([draft_invoice.id])
    end

    context 'when already applied to the plan' do
      it 'does not apply the tax once again' do
        create(:plan_applied_tax, tax:, plan:)
        expect { create_service.call }.not_to change(Plan::AppliedTax, :count)
      end
    end

    context 'when plan is not found' do
      let(:plan) { nil }

      it 'returns an error' do
        result = create_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.error_code).to eq('plan_not_found')
        end
      end
    end

    context 'when tax is not found' do
      let(:tax) { nil }

      it 'returns an error' do
        result = create_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.error_code).to eq('tax_not_found')
        end
      end
    end
  end
end
