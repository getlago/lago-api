# frozen_string_literal: true

module IntegrationCollectionMappings
  class NetsuiteCollectionMapping < BaseCollectionMapping
    settings_accessors :external_id, :external_account_code, :external_name
  end
end
