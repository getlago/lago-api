# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Events::PostValidationService, type: :service, transaction: false do
  subject(:validation_service) { described_class.new(organization:) }

  let(:organization) { create(:organization) }

  let(:invalid_code_event) do
    create(
      :event,
      organization:,
      code: Faker::Name.name.underscore,
      created_at: Time.current.beginning_of_hour - 25.minutes,
    )
  end

  let(:billable_metric) do
    create(
      :sum_billable_metric,
      organization:,
    )
  end

  let(:missing_aggregation_property_event) do
    create(
      :event,
      organization:,
      code: billable_metric.code,
      properties: {},
      created_at: Time.current.beginning_of_hour - 25.minutes,
    )
  end

  let(:billable_metric_with_group) do
    create(
      :sum_billable_metric,
      organization:,
    )
  end

  let(:parent_group) do
    create(:group, billable_metric: billable_metric_with_group)
  end

  let(:child_group) do
    create(
      :group,
      billable_metric: billable_metric_with_group,
      parent: parent_group,
      key: 'provider',
      value: 'aws',
    )
  end

  let(:missing_parent_group_key_event) do
    create(
      :event,
      organization:,
      code: billable_metric_with_group.code,
      properties: { billable_metric_with_group.field_name => 12 },
      created_at: Time.current.beginning_of_hour - 25.minutes,
    )
  end

  let(:missing_child_group_key_event) do
    create(
      :event,
      organization:,
      code: billable_metric_with_group.code,
      properties: {
        parent_group.key => parent_group.value,
        billable_metric_with_group.field_name => 12,
      },
      created_at: Time.current.beginning_of_hour - 25.minutes,
    )
  end

  before do
    child_group

    invalid_code_event
    missing_aggregation_property_event
    missing_parent_group_key_event
    missing_child_group_key_event

    Scenic.database.refresh_materialized_view(
      Events::LastHourMv.table_name,
      concurrently: false,
      cascade: false,
    )
  end

  describe '.call' do
    it 'checks last hour events returns the list of transaction_id' do
      result = validation_service.call

      expect(result.errors[:invalid_code]).to include(invalid_code_event.transaction_id)
      expect(result.errors[:missing_aggregation_property])
        .to include(missing_aggregation_property_event.transaction_id)
      expect(result.errors[:missing_group_key])
        .to include(
          missing_parent_group_key_event.transaction_id,
          missing_child_group_key_event.transaction_id,
        )
    end

    it 'delivers a webhook with the list of transaction_id' do
      validation_service.call

      expect(SendWebhookJob).to have_been_enqueued
        .with(
          'events.errors',
          organization,
          errors: {
            invalid_code: [invalid_code_event.transaction_id],
            missing_aggregation_property: [missing_aggregation_property_event.transaction_id],
            missing_group_key: [
              missing_parent_group_key_event.transaction_id,
              missing_child_group_key_event.transaction_id,
            ],
          }
        )
    end
  end
end
