# frozen_string_literal: true

class AddIndexOnEventExternalSubscriptionId < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    safety_assured do
      add_index(
        :events,
        %i[organization_id external_subscription_id code timestamp],
        name: 'index_events_on_external_subscription_id_and_code_and_timestamp',
        where: '(deleted_at IS NULL)'
      )
    end
  end
end
