# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Commitments::Minimum::CalculateTrueUpFeeService, type: :service do
  subject(:service) { described_class.new(invoice_subscription:) }

  let(:invoice_subscription) do
    create(
      :invoice_subscription,
      subscription:,
      from_datetime: DateTime.parse('2024-02-01T00:00:00'),
      to_datetime: DateTime.parse('2024-02-29T23:59:59'),
      timestamp: DateTime.parse('2024-03-05T10:00:00'),
    )
  end

  let(:subscription) { create(:subscription, customer:, plan:, billing_time:) }
  let(:customer) { create(:customer, organization:) }
  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:billing_time) { :calendar }

  describe '#call' do
    subject(:service_call) { service.call }

    context 'when plan has no minimum commitment' do
      it 'returns result with zero amount cents' do
        expect(service_call.amount_cents).to eq(0)
      end
    end

    context 'when plan has minimum commitment' do
      let(:commitment) { create(:commitment, plan:) }
      let(:commitment_amount_cents) { service.__send__(:commitment_amount_cents) }

      let(:true_up_fee_amount_cents) do
        commitment_amount_cents - invoice_subscription.total_amount_cents
      end

      before { commitment }

      context 'when there are no fees' do
        it 'returns result with amount cents' do
          expect(service_call.amount_cents).to eq(commitment_amount_cents)
        end
      end

      context 'when there are fees' do
        before do
          create(
            :fee,
            subscription: invoice_subscription.subscription,
            invoice: invoice_subscription.invoice,
          )
        end

        it 'returns result with amount cents' do
          expect(service_call.amount_cents).to eq(true_up_fee_amount_cents)
        end
      end
    end
  end
end
