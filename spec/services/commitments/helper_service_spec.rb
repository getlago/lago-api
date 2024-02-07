# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Commitments::HelperService, type: :service do
  let(:service) { described_class.new(commitment:, invoice_subscription:, current_usage: true) }
  let(:commitment) { create(:commitment, plan:) }
  let(:plan) { create(:plan, organization:) }
  let(:organization) { create(:organization) }
  let(:subscription) { create(:subscription, customer:, plan:) }
  let(:customer) { create(:customer, organization:) }

  let(:invoice_subscription) do
    create(
      :invoice_subscription,
      subscription:,
      from_datetime:,
      to_datetime:,
      charges_from_datetime:,
      charges_to_datetime:,
      timestamp:,
    )
  end

  let(:from_datetime) { DateTime.parse('2024-01-01T00:00:00') }
  let(:to_datetime) { DateTime.parse('2024-01-31T23:59:59') }
  let(:charges_from_datetime) { DateTime.parse('2024-01-01T00:00:00') }
  let(:charges_to_datetime) { DateTime.parse('2024-01-31T23:59:59') }
  let(:timestamp) { DateTime.parse('2024-02-01T10:00:00') }

  describe '#proration_coefficient' do
    subject(:apply_service) { service.proration_coefficient }

    context 'with whole period' do
      it 'returns proration coefficient' do
        expect(apply_service.proration_coefficient).to eq(1.0)
      end
    end

    context 'with partial period' do
      let(:from_datetime) { DateTime.parse('2024-01-15T00:00:00') }

      it 'returns proration coefficient' do
        expect(apply_service.proration_coefficient).to eq(0.5483870967741935)
      end
    end
  end

  describe '#period_invoice_ids' do
    subject(:apply_service) { service.period_invoice_ids }

    it 'returns ids of all subscription invoices for the period' do
      expect(apply_service.period_invoice_ids).to eq([invoice_subscription.invoice_id])
    end
  end
end
