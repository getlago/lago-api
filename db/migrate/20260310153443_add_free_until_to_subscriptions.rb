# frozen_string_literal: true

class AddFreeUntilToSubscriptions < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      change_table :subscriptions, bulk: true do |t|
        t.timestamptz :free_until

        t.check_constraint "free_until IS NULL OR free_until >= started_at",
          name: "free_until_should_be_after_start",
          validate: false

        t.check_constraint "free_until IS NULL OR ending_at IS NULL OR free_until <= ending_at",
          name: "free_until_should_be_before_end",
          validate: false
      end

      execute <<~SQL.squish
        CREATE FUNCTION ensure_subscription_consistency() RETURNS TRIGGER AS $$
          BEGIN
            IF OLD.free_until IS NOT NULL AND OLD.free_until IS DISTINCT FROM NEW.free_until THEN
              RAISE EXCEPTION 'free_until cannot be changed once set';
            END IF;
            RETURN NEW;
          END;
        $$ LANGUAGE plpgsql;

        CREATE TRIGGER ensure_consistency
        BEFORE UPDATE ON subscriptions
        FOR EACH ROW EXECUTE FUNCTION ensure_subscription_consistency();
      SQL
    end
  end

  # rubocop:disable Lago/NoDropColumnOrTable
  def down
    safety_assured do
      remove_column :subscriptions, :free_until

      execute "DROP FUNCTION IF EXISTS ensure_subscription_consistency();"
    end
  end
  # rubocop:enable Lago/NoDropColumnOrTable
end
