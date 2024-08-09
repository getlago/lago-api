# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LifetimeUsages::FlagRefreshFromInvoiceService, type: :service do
  subject(:flag_service) { described_class.new(invoice:) }

  let(:invoice) { create(:invoice, :subscription, subscriptions:) }
  let(:lifetime_usage) { create(:lifetime_usage, subscription: invoice.subscriptions.first) }

  let(:customer) { create(:customer) }
  let(:plan) { create(:plan, organization: customer.organization) }
  let(:subscriptions) { create_list(:subscription, 1, plan:) }

  let(:usage_thresold) { create(:usage_threshold, plan:) }

  before { usage_thresold }

  describe '.call' do
    it 'flags the lifetime usages for refresh' do
      expect { flag_service.call }
        .to change { lifetime_usage.reload.recalculate_invoiced_usage }.from(false).to(true)
    end

    context 'when the invoice is not subscription' do
      let(:invoice) { create(:invoice, invoice_type: 'one_off') }

      it { expect(flag_service.call).to be_success }
    end

    context 'when the invoice is not finalized or voided' do
      let(:invoice) { create(:invoice, :subscription, :draft) }

      it { expect(flag_service.call).to be_success }
    end

    context 'when the lifetime usage does not exists' do
      let(:lifetime_usage) { nil }

      it 'creates a new lifetime usage', aggregate_failures: true do
        expect { flag_service.call }
          .to change(LifetimeUsage, :count).by(1)

        expect(invoice.subscriptions.first.lifetime_usage.recalculate_invoiced_usage).to be(true)
      end
    end

    context 'when the invoice has no plan usage thresholds' do
      let(:usage_thresold) { nil }

      it 'does not flags the lifetime usage', aggregate_failures: true do
        expect(flag_service.call).to be_success
        expect(lifetime_usage.reload.recalculate_invoiced_usage).to be(false)
      end
    end
  end
end
