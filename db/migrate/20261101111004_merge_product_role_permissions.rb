# frozen_string_literal: true

class MergeProductRolePermissions < ActiveRecord::Migration[8.1]
  LEGACY_PERMISSIONS = %w[
    product_categories:view
    product_categories:create
    product_categories:update
    product_categories:delete
    product_filters:view
    product_filters:create
    product_filters:update
    product_filters:delete
  ].freeze

  def up
    safety_assured do
      execute <<~SQL
        UPDATE roles
        SET permissions = ARRAY(
          SELECT DISTINCT CASE permission
            WHEN 'product_categories:view' THEN 'products:view'
            WHEN 'product_categories:create' THEN 'products:create'
            WHEN 'product_categories:update' THEN 'products:update'
            WHEN 'product_categories:delete' THEN 'products:delete'
            WHEN 'product_filters:view' THEN 'products:view'
            WHEN 'product_filters:create' THEN 'products:create'
            WHEN 'product_filters:update' THEN 'products:update'
            WHEN 'product_filters:delete' THEN 'products:delete'
            ELSE permission
          END
          FROM unnest(roles.permissions) AS permission
          ORDER BY 1
        ),
        updated_at = CURRENT_TIMESTAMP
        WHERE organization_id IS NOT NULL
          AND permissions && ARRAY[#{LEGACY_PERMISSIONS.map { |permission| "'#{permission}'" }.join(", ")}]::varchar[]
      SQL
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Legacy product permissions cannot be restored from merged grants"
  end
end
