# frozen_string_literal: true

class Event < EventsRecord
  include Discard::Model
  self.discard_column = :deleted_at

  include CustomerTimezone
  include OrganizationTimezone

  belongs_to :organization

  validates :transaction_id, presence: true, uniqueness: {scope: %i[organization_id external_subscription_id]}
  validates :code, :external_subscription_id, presence: true

  default_scope -> { kept }
  scope :from_datetime, ->(from_datetime) { where('events.timestamp >= ?', from_datetime) }
  scope :to_datetime, ->(to_datetime) { where('events.timestamp <= ?', to_datetime) }

  def api_client
    metadata['user_agent']
  end

  def ip_address
    metadata['ip_address']
  end

  def billable_metric
    @billable_metric ||= organization.billable_metrics.find_by(code:)
  end

  def customer
    organization
      .customers
      .with_discarded
      .where(external_id: external_customer_id)
      .where('deleted_at IS NULL OR deleted_at > ?', timestamp)
      .order('deleted_at DESC NULLS LAST')
      .first
  end

  def subscription
    scope = if external_customer_id && customer
      if external_subscription_id
        customer.subscriptions.where(external_id: external_subscription_id)
      else
        customer.subscriptions
      end
    else
      organization.subscriptions.where(external_id: external_subscription_id)
    end

    scope
      .where("date_trunc('millisecond', started_at::timestamp) <= ?::timestamp", timestamp)
      .where(
        "terminated_at IS NULL OR date_trunc('millisecond', terminated_at::timestamp) >= ?",
        timestamp
      )
      .order('terminated_at DESC NULLS FIRST, started_at DESC')
      .first
  end
end

# == Schema Information
#
# Table name: events
#
#  id                         :uuid             not null, primary key
#  code                       :string           not null
#  deleted_at                 :datetime
#  metadata                   :jsonb            not null
#  precise_total_amount_cents :decimal(40, 15)
#  properties                 :jsonb            not null
#  timestamp                  :datetime
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  customer_id                :uuid
#  external_customer_id       :string
#  external_subscription_id   :string
#  organization_id            :uuid             not null
#  subscription_id            :uuid
#  transaction_id             :string           not null
#
# Indexes
#
#  index_events_on_customer_id                                      (customer_id)
#  index_events_on_deleted_at                                       (deleted_at)
#  index_events_on_external_subscription_id_and_code_and_timestamp  (organization_id,external_subscription_id,code,timestamp) WHERE (deleted_at IS NULL)
#  index_events_on_external_subscription_id_precise_amount          (external_subscription_id,code,timestamp) WHERE ((deleted_at IS NULL) AND (precise_total_amount_cents IS NOT NULL))
#  index_events_on_external_subscription_id_with_included           (external_subscription_id,code,timestamp) WHERE (deleted_at IS NULL)
#  index_events_on_organization_id                                  (organization_id)
#  index_events_on_organization_id_and_code                         (organization_id,code)
#  index_events_on_organization_id_and_code_and_created_at          (organization_id,code,created_at) WHERE (deleted_at IS NULL)
#  index_events_on_organization_id_and_timestamp                    (organization_id,timestamp) WHERE (deleted_at IS NULL)
#  index_events_on_properties                                       (properties) USING gin
#  index_events_on_subscription_id                                  (subscription_id)
#  index_events_on_subscription_id_and_code_and_timestamp           (subscription_id,code,timestamp) WHERE (deleted_at IS NULL)
#  index_unique_transaction_id                                      (organization_id,external_subscription_id,transaction_id) UNIQUE
#
