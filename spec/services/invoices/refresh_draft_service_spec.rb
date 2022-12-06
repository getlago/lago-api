# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::RefreshDraftService, type: :service do
  subject(:refresh_service) { described_class.new(invoice: invoice) }

  describe '#call' do
    let(:status) { :draft }
    let(:invoice) do
      create(:invoice, subscriptions: [subscription], status: status)
    end

    let(:started_at) { 1.month.ago }
    let(:subscription) do
      create(
        :subscription,
        subscription_at: started_at,
        started_at: started_at,
        created_at: started_at,
      )
    end

    before do
      allow(Invoices::CalculateFeesService).to receive(:call).and_call_original
    end

    context 'when invoice is finalized' do
      let(:status) { :finalized }

      it 'does not refresh it' do
        result = refresh_service.call
        expect(Invoices::CalculateFeesService).not_to have_received(:call)
        expect(result).to be_success
      end
    end

    it 'regenerates fees' do
      fee = create(:fee, invoice: invoice)
      create(:standard_charge, plan: subscription.plan, charge_model: 'standard')

      expect { refresh_service.call }
        .to change { invoice.reload.fees.count }.from(1).to(2)
        .and change { invoice.fees.pluck(:id).include?(fee.id) }.from(true).to(false)
    end

    it 'regenerates credits' do
      create(:credit, invoice: invoice)

      expect { refresh_service.call }
        .to change { invoice.reload.credits.count }.from(1).to(0)
    end

    it 'regenerates credit notes' do
      create(:credit_note, invoice: invoice)

      expect { refresh_service.call }
        .to change { invoice.reload.credit_notes.count }.from(1).to(0)
    end

    it 'regenerates wallet transactions' do
      create(:wallet_transaction, invoice: invoice)

      expect { refresh_service.call }
        .to change { invoice.reload.wallet_transactions.count }.from(1).to(0)
    end

    it 'updates issuing_date' do
      invoice.customer.update(timezone: 'America/New_York')

      freeze_time do
        expect { refresh_service.call }
          .to change { invoice.reload.issuing_date }.to(Time.current.to_date)
      end
    end

    it 'updates vat_rate' do
      invoice.customer.update(vat_rate: 15)

      expect { refresh_service.call }
        .to change { invoice.reload.vat_rate }.from(nil).to(15)
    end
  end
end
