# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PersistedEvents::ValidateCreationService, type: :service do
  subject(:validation_service) do
    described_class.new(
      subscription: subscription,
      billable_metric: billable_metric,
      args: args,
      result: result,
    )
  end

  let(:result) { BaseService::Result.new }
  let(:subscription) { create(:subscription) }
  let(:customer) { subscription.customer }

  let(:billable_metric) do
    create(
      :billable_metric,
      aggregation_type: 'recurring_count_agg',
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

  context 'without operation type' do
    let(:operation_type) { nil }

    it 'fails' do
      aggregate_failures do
        expect(validation_service).not_to be_valid
        expect(validation_service.errors.keys).to include(:operation_type)
        expect(validation_service.errors[:operation_type]).to eq(['invalid_operation_type'])
      end
    end
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

  context 'when operation type is add' do
    it { expect(validation_service).to be_valid }

    context 'with an active persisted metric' do
      before do
        create(
          :persisted_event,
          customer: customer,
          external_id: external_id,
          external_subscription_id: subscription.external_id,
        )
      end

      it 'fails' do
        aggregate_failures do
          expect(validation_service).not_to be_valid
          expect(validation_service.errors.keys).to include(billable_metric.field_name.to_sym)
          expect(validation_service.errors[billable_metric.field_name.to_sym])
            .to eq(['recurring_resource_already_added'])
        end
      end
    end

    context 'with removed persisted metric' do
      before do
        create(
          :persisted_event,
          customer: customer,
          external_id: external_id,
          external_subscription_id: subscription.external_id,
          removed_at: Time.current - 3.days,
        )
      end

      it { expect(validation_service).to be_valid }
    end
  end

  context 'when operation type is remove' do
    let(:operation_type) { 'remove' }

    context 'without persisted metric' do
      it 'fails' do
        aggregate_failures do
          expect(validation_service).not_to be_valid
          expect(validation_service.errors.keys).to include(billable_metric.field_name.to_sym)
          expect(validation_service.errors[billable_metric.field_name.to_sym]).to eq(['recurring_resource_not_found'])
        end
      end
    end

    context 'with an active persisted metric' do
      before do
        create(
          :persisted_event,
          customer: customer,
          external_id: external_id,
          external_subscription_id: subscription.external_id,
        )
      end

      it { expect(validation_service).to be_valid }
    end

    context 'with a removed persisted metric' do
      before do
        create(
          :persisted_event,
          customer: customer,
          external_id: external_id,
          external_subscription_id: subscription.external_id,
          removed_at: Time.current - 3.days,
        )
      end

      it 'fails' do
        aggregate_failures do
          expect(validation_service).not_to be_valid
          expect(validation_service.errors.keys).to include(billable_metric.field_name.to_sym)
          expect(validation_service.errors[billable_metric.field_name.to_sym]).to eq(['recurring_resource_not_found'])
        end
      end
    end
  end
end
