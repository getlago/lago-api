# frozen_string_literal: true

class AddStoredProcedureForTriggeringSubscription < ActiveRecord::Migration[7.1]
  def up
    safety_assured do
      execute "
  CREATE OR REPLACE PROCEDURE trigger_subscription_update(
      p_organization_id UUID,
      p_external_subscription_id varchar,
      result_id INOUT UUID
  )
  LANGUAGE plpgsql
  AS $$
  BEGIN
      INSERT INTO subscription_event_triggers (
          organization_id,
          external_subscription_id,
          created_at
      )
      VALUES (
          p_organization_id,
          p_external_subscription_id,
          NOW()
      )
      ON CONFLICT DO NOTHING
      RETURNING id INTO result_id;
  END;
  $$;"
    end
  end

  def down
    execute "DROP PROCEDURE trigger_subscription_update"
  end
end
