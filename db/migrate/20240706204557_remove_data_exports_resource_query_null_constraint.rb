class RemoveDataExportsResourceQueryNullConstraint < ActiveRecord::Migration[7.1]
  def change
    change_column_null :data_exports, :resource_query, true
  end
end
