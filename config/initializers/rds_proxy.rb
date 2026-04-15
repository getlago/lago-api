# frozen_string_literal: true

# Activates the RDS Proxy connection patch. See lib/lago/rds_proxy/connection_patch.rb
# for what the patch does and why.

if ENV["DATABASE_VIA_RDS_PROXY"].present?
  require "lago/rds_proxy/connection_patch"

  # The pg gem auto-sends SET client_encoding when default_internal is set,
  # bypassing configure_connection. Reset to nil to suppress.
  Encoding.default_internal = nil

  ActiveSupport.on_load(:active_record) do
    ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.prepend(
      Lago::RdsProxy::ConnectionPatch
    )
  end
end
