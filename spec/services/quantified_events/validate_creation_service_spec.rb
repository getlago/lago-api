# frozen_string_literal: true

require 'rails_helper'

RSpec.describe QuantifiedEvents::ValidateCreationService, type: :service do
  subject(:validation_service) do
    described_class.new(
      subscription:,
      billable_metric:,
      args:,
      result:,
    )
  end

  let(:result) { BaseService::Result.new }
  let(:subscription) { create(:subscription) }
  let(:customer) { subscription.customer }
  let(:organization) { customer.organization }

  let(:billable_metric) do
    create(
      :billable_metric,
      aggregation_type: 'unique_count_agg',
      organization: customer.organization,
      field_name: 'item_id',
    )
  end

  let(:args) do
    {
      code: billable_metric.code,
      properties: {
        'item_id' => external_id,
        'operation_type' => operation_type,
      },
    }.with_indifferent_access
  end

  let(:external_id) { 'ext_12345' }
  let(:operation_type) { 'add' }

  context 'without operation type for unique_count_agg metric' do
    let(:operation_type) { nil }
    let(:billable_metric) do
      create(
        :billable_metric,
        aggregation_type: 'unique_count_agg',
        organization: customer.organization,
        field_name: 'item_id',
      )
    end

    it { expect(validation_service).to be_valid }
  end

  context 'with invalid operation type' do
    let(:operation_type) { 'invalid' }

    it 'fails' do
      aggregate_failures do
        expect(validation_service).not_to be_valid
        expect(validation_service.errors.keys).to include(:operation_type)
        expect(validation_service.errors[:operation_type]).to eq(['invalid_operation_type'])
      end
    end
  end

  context 'when operation type is remove' do
    let(:operation_type) { 'remove' }

    context 'without quantified metric' do
      it 'fails' do
        aggregate_failures do
          expect(validation_service).not_to be_valid
          expect(validation_service.errors.keys).to include(billable_metric.field_name.to_sym)
          expect(validation_service.errors[billable_metric.field_name.to_sym]).to eq(['resource_not_found'])
        end
      end
    end

    context 'with an active quantified metric' do
      before do
        create(
          :quantified_event,
          organization:,
          external_id:,
          external_subscription_id: subscription.external_id,
        )
      end

      it { expect(validation_service).to be_valid }
    end

    context 'with a removed quantified metric' do
      before do
        create(
          :quantified_event,
          organization:,
          external_id:,
          external_subscription_id: subscription.external_id,
          removed_at: Time.current - 3.days,
        )
      end

      it 'fails' do
        aggregate_failures do
          expect(validation_service).not_to be_valid
          expect(validation_service.errors.keys).to include(billable_metric.field_name.to_sym)
          expect(validation_service.errors[billable_metric.field_name.to_sym]).to eq(['resource_not_found'])
        end
      end
    end
  end
end
