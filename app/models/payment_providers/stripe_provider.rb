# frozen_string_literal: true

module PaymentProviders
  class StripeProvider < BaseProvider
    StripePayment = Data.define(:id, :status, :metadata)

    SUCCESS_REDIRECT_URL = 'https://stripe.com/'

    # NOTE: find the complete list of event types at https://stripe.com/docs/api/events/types
    WEBHOOKS_EVENTS = %w[
      setup_intent.succeeded
      payment_intent.payment_failed
      payment_intent.succeeded
      payment_method.detached
      charge.refund.updated
      customer.updated
      charge.succeeded
      charge.dispute.closed
    ].freeze

    PENDING_STATUSES = %w[
      processing
      requires_capture
      requires_action
      requires_confirmation
      requires_payment_method
    ].freeze
    SUCCESS_STATUSES = %w[succeeded].freeze
    FAILED_STATUSES = %w[canceled].freeze

    validates :secret_key, presence: true
    validates :success_redirect_url, url: true, allow_nil: true, length: {maximum: 1024}

    settings_accessors :webhook_id
    secrets_accessors :secret_key
  end
end

# == Schema Information
#
# Table name: payment_providers
#
#  id              :uuid             not null, primary key
#  code            :string           not null
#  deleted_at      :datetime
#  name            :string           not null
#  secrets         :string
#  settings        :jsonb            not null
#  type            :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :uuid             not null
#
# Indexes
#
#  index_payment_providers_on_code_and_organization_id  (code,organization_id) UNIQUE WHERE (deleted_at IS NULL)
#  index_payment_providers_on_organization_id           (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
