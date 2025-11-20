# frozen_string_literal: true

class CreateItemMetadata < ActiveRecord::Migration[8.0]
  def up
    create_table :item_metadata, id: :uuid do |t|
      t.references :organization,
        null: false,
        type: :uuid,
        foreign_key: {on_delete: :cascade},
        comment: "Reference to the organization"
      t.string :owner_type, null: false, comment: "Polymorphic owner type"
      t.uuid :owner_id, null: false, comment: "Polymorphic owner id"
      t.jsonb :value, null: false, default: {}, comment: "item_metadata key-value pairs"
      t.timestamps

      t.index [:owner_type, :owner_id], unique: true
      t.index [:id, :owner_id, :organization_id], unique: true, name: "index_item_metadata_for_fk"
      t.index :value, name: "index_item_metadata_on_value", using: :gin
    end

    safety_assured do
      execute <<-SQL.squish
        CREATE OR REPLACE FUNCTION validate_item_metadata_value()
        RETURNS trigger AS $$
        DECLARE
          key_count integer;
          key_name text;
          key_value text;
          key_length integer;
          val_length integer;
          val_type text;
        BEGIN
          IF jsonb_typeof(NEW.value) != 'object' THEN
            RAISE EXCEPTION 'metadata value must be a JSON object';
          END IF;
        
          SELECT count(*) INTO key_count FROM jsonb_object_keys(NEW.value);
          IF key_count > 50 THEN
            RAISE EXCEPTION 'metadata cannot have more than 50 keys (found %)', key_count;
          END IF;

          FOR key_name IN SELECT jsonb_object_keys(NEW.value)
          LOOP
            key_length := length(key_name);
            key_value := NEW.value->>key_name;
            val_length := length(key_value);
            val_type := jsonb_typeof(NEW.value->key_name);

            IF key_length > 40 THEN
              RAISE EXCEPTION 'metadata key length cannot exceed 40 characters (key "%" has % characters)', key_name, key_length;
            END IF;

            IF val_type NOT IN ('null', 'string') THEN
              RAISE EXCEPTION 'metadata values must be nulls or strings (key "%" has type %)', key_name, val_type;
            END IF;

            IF val_length > 255 THEN
              RAISE EXCEPTION 'metadata value length cannot exceed 255 characters (key "%" has value with % characters)', key_name, val_length;
            END IF;
          END LOOP;

          RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
      SQL

      execute <<-SQL.squish
        CREATE TRIGGER validate_item_metadata_value
        BEFORE INSERT OR UPDATE ON item_metadata
        FOR EACH ROW
        EXECUTE FUNCTION validate_item_metadata_value();
      SQL
    end
  end

  def down
    drop_table :item_metadata

    safety_assured do
      execute <<-SQL.squish
        DROP FUNCTION IF EXISTS validate_item_metadata_value;
      SQL
    end
  end
end
