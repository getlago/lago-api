# frozen_string_literal: true

module IntegrationCollectionMappings
  class NetsuiteCollectionMapping < BaseCollectionMapping
    settings_accessors :netsuite_id, :netsuite_account_code, :netsuite_name

    MAPPING_TYPES = %i[fallback_item coupon subscription_fee minimum_commitment tax prepaid_credit].freeze

    enum mapping_type: MAPPING_TYPES
  end
end
