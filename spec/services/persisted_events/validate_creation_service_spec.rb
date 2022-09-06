# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PersistedEvents::ValidateCreationService, type: :service do
  subject(:validate_result) do
    described_class.call(
      subscription: subscription,
      billable_metric: billable_metric,
      params: params,
    )
  end

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

  let(:params) do
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

    it { expect(validate_result).to eq('invalid_operation_type') }
  end

  context 'with invalid operation type' do
    let(:operation_type) { 'invalid' }

    it { expect(validate_result).to eq('invalid_operation_type') }
  end

  context 'when operation type is add' do
    it { expect(validate_result).to be_nil }

    context 'with an active persisted metric' do
      before do
        create(
          :persisted_event,
          customer: customer,
          external_id: external_id,
          external_subscription_id: subscription.external_id,
        )
      end

      it { expect(validate_result).to eq('recurring_resource_already_added') }
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

      it { expect(validate_result).to be_nil }
    end
  end

  context 'when operation type is remove' do
    let(:operation_type) { 'remove' }

    context 'without persisted metric' do
      it { expect(validate_result).to eq('recurring_resource_not_found') }
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

      it { expect(validate_result).to be_nil }
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

      it { expect(validate_result).to eq('recurring_resource_not_found') }
    end
  end
end
