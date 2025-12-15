# frozen_string_literal: true

class CreateRoles < ActiveRecord::Migration[8.0]
  def up
    create_table :roles, id: :uuid do |t|
      t.string :name, null: false
      t.boolean :admin, null: false, default: false
      t.text :permissions, array: true, null: false, default: []
      t.references :organization, type: :uuid
      t.text :description
      t.datetime :deleted_at
      t.timestamps

      t.check_constraint "name <> ''", name: "name_not_empty"
      t.check_constraint "length(name) <= 100", name: "name_max_length"
      t.check_constraint "length(description) <= 255", name: "description_max_length"
      t.check_constraint "organization_id IS NOT NULL OR cardinality(permissions) = 0", name: "predefined_role_cannot_have_permissions"
      t.check_constraint "organization_id IS NULL OR cardinality(permissions) > 0", name: "custom_role_should_have_permissions"
      t.check_constraint "NOT (permissions::text ~ '([\\{,]:|::|:[,\\}])') AND NOT ('' = ANY(permissions))", name: "permissions_has_no_empty_parts"

      t.index :admin,
        unique: true,
        where: "admin AND deleted_at IS NULL",
        name: "index_roles_by_unique_admin"
      t.index "organization_id NULLS FIRST, lower(name)",
        unique: true,
        where: "deleted_at IS NULL",
        name: "index_roles_by_name_per_organization"
    end

    safety_assured do
      execute <<~SQL.squish
        INSERT INTO roles (admin, name, description, permissions, created_at, updated_at)
        VALUES
            (
              true,
              'Admin',
              'Administrator having all permissions',
              ARRAY[]::text[],
              now(),
              now()
            ),
            (
              false,
              'Finance',
              'Finance role with permissions to manage financial data',
              ARRAY[]::text[],
              now(),
              now()
            ),
            (
              false,
              'Manager',
              'The predefined manager role',
              ARRAY[]::text[],
              now(),
              now()
            );
  
        CREATE FUNCTION ensure_role_consistency() RETURNS TRIGGER AS $$
          BEGIN
            IF TG_OP = 'DELETE' THEN
              RAISE EXCEPTION 'Hard deletion of roles is not allowed; use soft deletion instead';
            ELSIF OLD.deleted_at IS NOT NULL THEN
              RAISE EXCEPTION 'Deleted role cannot be modified';
            ELSIF OLD.organization_id IS NULL THEN
              RAISE EXCEPTION 'Predefined role cannot be modified';
            ELSIF OLD.organization_id IS DISTINCT FROM NEW.organization_id THEN
              RAISE EXCEPTION 'Custom role cannot be moved to another organization';
            ELSIF NEW.permissions != OLD.permissions THEN
              NEW.permissions := ARRAY(SELECT DISTINCT unnest(NEW.permissions) ORDER BY 1);
            END IF;

            RETURN NEW;
          END;
        $$ LANGUAGE plpgsql;

        CREATE TRIGGER ensure_consistency
        BEFORE UPDATE OR DELETE ON roles
        FOR EACH ROW EXECUTE FUNCTION ensure_role_consistency();
      SQL
    end
  end

  def down
    drop_table :roles

    safety_assured { execute "DROP FUNCTION IF EXISTS ensure_role_consistency();" }
  end
end
