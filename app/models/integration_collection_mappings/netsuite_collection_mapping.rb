# frozen_string_literal: true

module IntegrationCollectionMappings
  class NetsuiteCollectionMapping < BaseCollectionMapping
    settings_accessors :netsuite_id, :netsuite_account_code, :netsuite_name
  end
end
