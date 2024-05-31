# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Customers::DestroyService, type: :service do
  subject(:destroy_service) { described_class.new(customer:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }

  before { customer }

  describe '#call' do
    it 'soft deletes the customer' do
      freeze_time do
        expect { destroy_service.call }.to change(Customer, :count).by(-1)
          .and change { customer.reload.deleted_at }.from(nil).to(Time.current)
      end
    end

    it 'enqueues a job to terminates the customer resources' do
      destroy_service.call

      expect(Customers::TerminateRelationsJob).to have_been_enqueued
        .with(customer_id: customer.id)
    end

    it 'calls SegmentTrackJob' do
      allow(SegmentTrackJob).to receive(:perform_later)

      customer = destroy_service.call.customer

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: 'customer_deleted',
        properties: {
          customer_id: customer.id,
          deleted_at: customer.deleted_at,
          organization_id: customer.organization_id
        }
      )
    end

    context 'when customer is not found' do
      let(:customer) { nil }

      it 'returns an error' do
        result = destroy_service.call

        expect(result).not_to be_success
        expect(result.error.error_code).to eq('customer_not_found')
      end
    end
  end
end
