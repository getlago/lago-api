# frozen_string_literal: true

module IntegrationMappings
  class NetsuiteMapping < BaseMapping
    settings_accessors :netsuite_id, :netsuite_account_code, :netsuite_name

    MAPPABLE_TYPES = %i[AddOn BillableMetric].freeze
  end
end
