# frozen_string_literal: true

module Clickhouse
  class ActivityLog < BaseRecord
    self.table_name = "activity_logs"
    self.primary_key = nil

    belongs_to :organization
    belongs_to :resource, polymorphic: true

    before_save :ensure_activity_id

    def user
      organization.users.find_by(id: user_id)
    end

    def api_key
      organization.api_keys.find_by(id: api_key_id)
    end

    def customer
      organization.customers.find_by(external_id: external_customer_id)
    end

    def subscription
      organization.subscriptions.find_by(external_id: external_subscription_id)
    end

    private

    def ensure_activity_id
      self.activity_id = SecureRandom.uuid if activity_id.blank?
    end
  end
end

# == Schema Information
#
# Table name: activity_logs
#
#  activity_object          :string
#  activity_object_changes  :string
#  activity_source          :Enum8('api' = 1, not null
#  activity_type            :string           not null
#  logged_at                :datetime         not null
#  resource_type            :string           not null
#  created_at               :datetime         not null
#  activity_id              :string           not null
#  api_key_id               :string
#  external_customer_id     :string
#  external_subscription_id :string
#  organization_id          :string           not null
#  resource_id              :string           not null
#  user_id                  :string
#
