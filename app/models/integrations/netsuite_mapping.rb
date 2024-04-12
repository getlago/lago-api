# frozen_string_literal: true

module Integrations
  class NetsuiteMapping < BaseMapping
    settings_accessors :netsuite_id, :netsuite_account_code, :netsuite_name
  end
end
