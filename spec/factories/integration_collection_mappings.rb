# frozen_string_literal: true

FactoryBot.define do
  factory :netsuite_collection_mapping, class: 'IntegrationCollectionMappings::NetsuiteCollectionMapping' do
    association :integration, factory: :netsuite_integration
    mapping_type { %i[fallback_item coupon subscription_fee minimum_commitment tax prepaid_credit].sample }

    settings do
      {
        external_id: 'netsuite-123',
        external_account_code: 'netsuite-code-1',
        external_name: 'Credits and Discounts'
      }
    end
  end

  factory :xero_collection_mapping, class: 'IntegrationCollectionMappings::XeroCollectionMapping' do
    association :integration, factory: :xero_integration
    mapping_type { %i[fallback_item coupon subscription_fee minimum_commitment tax prepaid_credit account].sample }

    settings do
      {
        external_id: 'xero-123',
        external_account_code: 'xero-code-1',
        external_name: 'Credits and Discounts'
      }
    end
  end
end
