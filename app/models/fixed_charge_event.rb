class FixedChargeEvent < ApplicationRecord
  belongs_to :organization
  belongs_to :customer
  belongs_to :subscription
end

# == Schema Information
#
# Table name: fixed_charge_events
#
#  id              :uuid             not null, primary key
#  code            :string
#  deleted_at      :datetime
#  properties      :jsonb
#  timestamp       :datetime
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  customer_id     :uuid             not null
#  organization_id :uuid             not null
#  subscription_id :uuid             not null
#
# Indexes
#
#  index_fixed_charge_events_on_code             (code)
#  index_fixed_charge_events_on_customer_id      (customer_id)
#  index_fixed_charge_events_on_organization_id  (organization_id)
#  index_fixed_charge_events_on_subscription_id  (subscription_id)
#
# Foreign Keys
#
#  fk_rails_...  (customer_id => customers.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (subscription_id => subscriptions.id)
#
