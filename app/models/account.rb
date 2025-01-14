# frozen_string_literal: true

class Account < ApplicationRecord
  include CustomerTimezone
  include OrganizationTimezone
  include PaperTrailTraceable
  include Discard::Model
  self.discard_column = :deleted_at

  self.table_name = :customers
  self.inheritance_column = :account_type

  belongs_to :organization

  has_many :invoices, foreign_key: :customer_id
end

# == Schema Information
#
# Table name: customers
#
#  id                               :uuid             not null, primary key
#  account_type                     :string
#  address_line1                    :string
#  address_line2                    :string
#  city                             :string
#  country                          :string
#  currency                         :string
#  customer_type                    :enum
#  deleted_at                       :datetime
#  document_locale                  :string
#  email                            :string
#  exclude_from_dunning_campaign    :boolean          default(FALSE), not null
#  finalize_zero_amount_invoice     :integer          default("inherit"), not null
#  firstname                        :string
#  invoice_grace_period             :integer
#  last_dunning_campaign_attempt    :integer          default(0), not null
#  last_dunning_campaign_attempt_at :datetime
#  lastname                         :string
#  legal_name                       :string
#  legal_number                     :string
#  logo_url                         :string
#  name                             :string
#  net_payment_term                 :integer
#  payment_provider                 :string
#  payment_provider_code            :string
#  phone                            :string
#  shipping_address_line1           :string
#  shipping_address_line2           :string
#  shipping_city                    :string
#  shipping_country                 :string
#  shipping_state                   :string
#  shipping_zipcode                 :string
#  skip_invoice_custom_sections     :boolean          default(FALSE), not null
#  slug                             :string
#  state                            :string
#  tax_identification_number        :string
#  timezone                         :string
#  url                              :string
#  vat_rate                         :float
#  zipcode                          :string
#  created_at                       :datetime         not null
#  updated_at                       :datetime         not null
#  applied_dunning_campaign_id      :uuid
#  external_id                      :string           not null
#  external_salesforce_id           :string
#  organization_id                  :uuid             not null
#  sequential_id                    :bigint
#
# Indexes
#
#  index_customers_on_applied_dunning_campaign_id      (applied_dunning_campaign_id)
#  index_customers_on_deleted_at                       (deleted_at)
#  index_customers_on_external_id_and_organization_id  (external_id,organization_id) UNIQUE WHERE (deleted_at IS NULL)
#  index_customers_on_organization_id                  (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (applied_dunning_campaign_id => dunning_campaigns.id)
#  fk_rails_...  (organization_id => organizations.id)
#
