# frozen_string_literal: true

module Integrations
  class AgentStorefrontIntegration < BaseIntegration
    validates :code, :payment_provider_code, :scope, presence: true
    validate :https_urls
    validate :stripe_provider_exists
    validate :validate_plans, if: :plans_changed?

    has_many :agent_registrations, class_name: "Agents::Registration", foreign_key: :integration_id, dependent: :delete_all

    PLAN_KEYS = %w[plan_code minimum_topup_cents maximum_topup_cents].freeze

    settings_accessors :payment_provider_code, :resource_endpoint, :resource_instructions, :scope
    settings_accessors :plans, default: []

    scope :with_payment_provider_code, ->(code) { where("settings->>'payment_provider_code' = ?", code) }
    scope :with_plan_code, ->(code) { where("settings->'plans' @> ?::jsonb", [{plan_code: code}].to_json) }

    def stripe_provider
      organization&.stripe_payment_providers&.find_by(code: payment_provider_code)
    end

    def agent_url
      "#{ENV["LAGO_API_URL"]}/agents/v1/#{id}"
    end

    def plans=(value)
      entries = Array.wrap(value).map { it.respond_to?(:to_h) ? it.to_h.stringify_keys.slice(*PLAN_KEYS) : {} }
      push_to_settings(key: "plans", value: entries)
    end

    def plans_for_sale
      organization.plans.parents.where(pending_deletion: false, code: plans.map { it["plan_code"] })
    end

    def sold_plan(code)
      plans.find { it["plan_code"] == code }
    end

    def enrolled_agents?
      external_ids = agent_registrations.select(:id).map { Agents::ExternalIds.subscription(it) }
      organization.subscriptions.active.where(external_id: external_ids).exists?
    end

    private

    def plans_changed?
      attribute_in_database(:settings).to_h["plans"] != settings.to_h["plans"]
    end

    def validate_plans
      codes = plans.map { it["plan_code"] }

      if codes.uniq.size != codes.size || !plans.all? { valid_topup_bounds?(it) }
        errors.add(:plans, "value_is_invalid")
      elsif !(codes - plans_for_sale.pluck(:code)).empty?
        errors.add(:plans, "plan_not_found")
      end
    end

    def valid_topup_bounds?(sold_plan)
      minimum, maximum = sold_plan.values_at("minimum_topup_cents", "maximum_topup_cents")

      [minimum, maximum].compact.all? { it.is_a?(Integer) && it.positive? } &&
        (minimum.nil? || maximum.nil? || maximum >= minimum)
    end

    def https_urls
      %i[resource_endpoint resource_instructions].each do |attribute|
        value = public_send(attribute)
        next if value.blank?

        uri = URI.parse(value)
        errors.add(attribute, :url_invalid) unless uri.is_a?(URI::HTTPS) && uri.host.present?
      rescue URI::InvalidURIError
        errors.add(attribute, :url_invalid)
      end
    end

    def stripe_provider_exists
      return if payment_provider_code.blank?

      errors.add(:payment_provider_code, "payment_provider_not_found") unless stripe_provider
    end
  end
end

# == Schema Information
#
# Table name: integrations
# Database name: primary
#
#  id              :uuid             not null, primary key
#  code            :string           not null
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
#  index_integrations_on_code_and_organization_id  (code,organization_id) UNIQUE
#  index_integrations_on_organization_id           (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
