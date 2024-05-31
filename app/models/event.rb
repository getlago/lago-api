# frozen_string_literal: true

class Event < EventsRecord
  include Discard::Model
  self.discard_column = :deleted_at

  include CustomerTimezone
  include OrganizationTimezone

  belongs_to :organization

  validates :transaction_id, presence: true, uniqueness: {scope: %i[organization_id external_subscription_id]}
  validates :code, presence: true

  default_scope -> { kept }
  scope :from_datetime, ->(from_datetime) { where('events.timestamp::timestamp(0) >= ?', from_datetime) }
  scope :to_datetime, ->(to_datetime) { where('events.timestamp::timestamp(0) <= ?', to_datetime) }

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
