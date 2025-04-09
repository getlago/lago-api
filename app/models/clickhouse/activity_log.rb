# frozen_string_literal: true

module Clickhouse
  class ActivityLog < BaseRecord
    self.table_name = "activity_logs"
    self.primary_key = nil

    before_save :ensure_activity_id

    #def id
      #"#{organization_id}-#{activity_type}-#{activity_source}-#{logged_at.to_i}"
    #end

    def organization
      Organization.find_by(id: organization_id)
    end

    def user
      organization.users.find_by(id: user_id)
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
#  activity_source :Enum8('api' = 1, not null
#  activity_type   :date             not null
#  logged_at       :datetime         not null
#  object          :string
#  object_changes  :string
#  created_at      :datetime         not null
#  activity_id     :string           not null
#  api_key_id      :string
#  organization_id :string           not null
#  user_id         :string
#
