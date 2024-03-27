# frozen_string_literal: true

class FillPropertiesOnPersistedEvents < ActiveRecord::Migration[7.0]
  class PersistedEvent < ApplicationRecord; end

  def change
    PersistedEvent.unscoped.find_each do |persisted_event|
      event = Event.unscoped.where(
        organization_id: persisted_event.billable_metric.organization_id,
        customer_id: persisted_event.customer_id
      ).where(
        "properties -> '#{persisted_event.billable_metric.field_name}' = ?",
        persisted_event.external_id
      ).first

      persisted_event.update!(properties: event.properties)
    end
  end
end
