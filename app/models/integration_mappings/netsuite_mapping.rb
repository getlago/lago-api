# frozen_string_literal: true

module IntegrationMappings
  class NetsuiteMapping < BaseMapping
    belongs_to :mappable, polymorphic: true

    settings_accessors :external_id, :external_account_code, :external_name
  end
end
