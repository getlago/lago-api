# frozen_string_literal: true

# Loads `db/structure.sql` into the schema configured with `POSTGRES_SCHEMA`.
# See lib/lago/database/structure_load_patch.rb for what the patch does and why.

require "lago/database/structure_load_patch"

ActiveSupport.on_load(:active_record) do
  ActiveRecord::Tasks::PostgreSQLDatabaseTasks.prepend(Lago::Database::StructureLoadPatch)
end
